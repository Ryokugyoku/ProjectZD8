import Foundation

/// プロセス復帰時に未終了だったセッションへ、プロセス終了の欠損を記録して続行か終了かを決めます。
///
/// 手順: 開いたままの区間を最後にcommitしたRawの時刻で `processTerminated` として閉じ → その時刻から現在までを
/// `processTerminated` の欠損として記録 → `AcquisitionRelaunchPolicy`(実時間)で判定します。猶予内なら欠損を
/// 未終了のまま残し(次の取得開始で `processRelaunched` の区間を開き、欠損を閉じます)、未確定batchだけを回復します。
/// 猶予を超えたら欠損を現在時刻で閉じ、最後にcommitした時刻をセッションの終了時刻として終了します。
/// プロセス終了で未確定のまま残ったbatchの回復はこのuse caseが呼ぶRepositoryの1か所で行い、二重に処理しません。
struct RecoverRelaunchedConnectionSessionUseCase {
    /// 最後にcommitしたRawを読む境界です。
    private let rawLogRepository: any ConnectionSessionRawLogRepository
    /// 連続取得区間を保存する境界です。
    private let segmentRepository: any ConnectionSessionSegmentRepository
    /// 欠損を保存する境界です。
    private let gapRepository: any ConnectionSessionGapRepository
    /// 中断sessionのbatch回復と終了を行う境界です。
    private let terminationRepository: any ConnectionSessionAcquisitionTerminationRepository
    /// 続行か終了かを判定する方針です。
    private let policy = AcquisitionRelaunchPolicy()

    /// 保存先を固定します。
    ///
    /// 責務: プロセス復帰の処理に使う保存先を注入します。
    /// - Parameters:
    ///   - rawLogRepository: 最後にcommitしたRawを読む境界。
    ///   - segmentRepository: 連続取得区間を保存する境界。
    ///   - gapRepository: 欠損を保存する境界。
    ///   - terminationRepository: 中断sessionのbatch回復と終了を行う境界。
    init(
        rawLogRepository: any ConnectionSessionRawLogRepository,
        segmentRepository: any ConnectionSessionSegmentRepository,
        gapRepository: any ConnectionSessionGapRepository,
        terminationRepository: any ConnectionSessionAcquisitionTerminationRepository
    ) {
        self.rawLogRepository = rawLogRepository
        self.segmentRepository = segmentRepository
        self.gapRepository = gapRepository
        self.terminationRepository = terminationRepository
    }

    /// 1件の未終了セッションにプロセス終了を記録し、続行か終了かを決めます。
    ///
    /// 責務: 区間の終了・欠損の記録・判定・batch回復またはセッション終了を順に行います。
    /// - Parameters:
    ///   - session: プロセス復帰時に未終了だったセッション。
    ///   - now: 判定する時点の実時間。
    /// - Returns: 続行可能なら `.resumable`、終了したら `.ended`。
    /// - Throws: 読取または保存の失敗。
    func recover(_ session: ConnectionSession, now: Date) throws -> ConnectionSessionRelaunchOutcome {
        let lastCommitted = try lastCommittedEntry(of: session.id)
        let lastCommittedAt = max(lastCommitted?.observedAt ?? session.startedAt, session.startedAt)
        let isResumable = policy.decision(lastCommittedAt: lastCommittedAt, now: now) == .continueWaiting
        try closeOpenSegment(of: session.id, at: lastCommittedAt, lastSequence: lastCommitted?.sequence)
        try recordTerminationGap(of: session.id, startedAt: lastCommittedAt, endedAt: isResumable ? nil : max(now, lastCommittedAt))
        guard isResumable else {
            return .ended(try terminationRepository.finishInterruptedSessionAcquisition(session, endedAt: lastCommittedAt))
        }
        try terminationRepository.sealInterruptedBatches(for: session.id, completedAt: lastCommittedAt)
        return .resumable(session, lastCommittedAt: lastCommittedAt)
    }

    /// 続行可能だったセッションを、続けずに終了します。
    ///
    /// 責務: 未終了の `processTerminated` 欠損を現在時刻で閉じ、最後にcommitした時刻でセッションを終了します。
    /// - Parameters:
    ///   - session: 続行可能だったセッション。
    ///   - lastCommittedAt: 最後にcommitしたRawの観測時刻。
    ///   - now: 終了を決めた時点の実時間。
    /// - Returns: 終了済みセッション。
    /// - Throws: 読取または保存の失敗。
    func end(_ session: ConnectionSession, lastCommittedAt: Date, now: Date) throws -> ConnectionSession {
        if let open = try gapRepository.gaps(for: session.id).last, open.endedAt == nil {
            try gapRepository.finishGap(
                ordinal: open.gapOrdinal,
                for: session.id,
                endedAt: max(now, open.startedAt),
                followingSegmentOrdinal: nil
            )
        }
        return try terminationRepository.finishInterruptedSessionAcquisition(session, endedAt: lastCommittedAt)
    }

    /// 最後にcommitしたRawを返します。
    ///
    /// 責務: 欠番なしで続く記録順序の最後の1件だけを読みます。
    /// - Parameter sessionID: 読取対象のセッション。
    /// - Returns: 最後のRaw。Rawが無ければ `nil`。
    /// - Throws: 読取の失敗。
    private func lastCommittedEntry(of sessionID: ConnectionSessionID) throws -> ConnectionSessionRawLogEntry? {
        let count = try rawLogRepository.entryCount(for: sessionID)
        guard count > 0 else { return nil }
        let after: Int64? = count >= 2 ? Int64(count - 2) : nil
        return try rawLogRepository.entries(for: sessionID, after: after, limit: 1).last
    }

    /// 開いたままの区間をプロセス終了として閉じます。
    ///
    /// 責務: 最後の区間が未終了なら、最後にcommitした時刻と記録順序で `processTerminated` として終了します。
    /// - Parameters:
    ///   - sessionID: 区間を所有するセッション。
    ///   - endedAt: 最後にcommitしたRawの観測時刻。
    ///   - lastSequence: 最後にcommitした記録順序。
    /// - Throws: 読取または保存の失敗。
    private func closeOpenSegment(of sessionID: ConnectionSessionID, at endedAt: Date, lastSequence: Int64?) throws {
        guard let last = try segmentRepository.segments(for: sessionID).last, last.endedAt == nil else { return }
        try segmentRepository.finishSegment(
            ordinal: last.segmentOrdinal,
            for: sessionID,
            endedAt: max(endedAt, last.startedAt),
            reason: .processTerminated,
            lastSequence: lastSequence.flatMap { $0 >= last.firstSequence ? $0 : nil }
        )
    }

    /// 最後にcommitした時刻からの `processTerminated` の欠損を記録します。
    ///
    /// 責務: 区間が1件以上ある場合だけ欠損を保存します。前回の復帰で残した未終了の欠損があれば新しく作らず、
    /// 終了する場合だけそれを閉じます。
    /// - Parameters:
    ///   - sessionID: 欠損を所有するセッション。
    ///   - startedAt: 最後にcommitしたRawの観測時刻。
    ///   - endedAt: 終了する場合の欠損の終了時刻。続行可能なら `nil`(未終了のまま残します)。
    /// - Throws: 読取または保存の失敗。
    private func recordTerminationGap(of sessionID: ConnectionSessionID, startedAt: Date, endedAt: Date?) throws {
        guard let lastSegment = try segmentRepository.segments(for: sessionID).last else { return }
        let gaps = try gapRepository.gaps(for: sessionID)
        if let open = gaps.last, open.endedAt == nil {
            guard let endedAt else { return }
            try gapRepository.finishGap(
                ordinal: open.gapOrdinal,
                for: sessionID,
                endedAt: max(endedAt, open.startedAt),
                followingSegmentOrdinal: nil
            )
            return
        }
        try gapRepository.saveGap(
            ConnectionSessionGap(
                gapOrdinal: (gaps.last?.gapOrdinal ?? -1) + 1,
                precedingSegmentOrdinal: lastSegment.segmentOrdinal,
                startedAt: startedAt,
                endedAt: endedAt,
                cause: .processTerminated
            ),
            for: sessionID
        )
    }
}
