import Foundation

/// 取得開始時にセッションの次の連続取得区間を開始し、欠損番号の続きを求めます。
///
/// プロセス復帰の判定で残した未終了の `processTerminated` 欠損があれば、新しい区間を
/// `processRelaunched` で開始し、その欠損へ終了時刻と直後の区間を確定します。
nonisolated struct AcquisitionSegmentOpener: Sendable {
    /// 開始した区間と、次に使う欠損番号です。
    struct Opened: Equatable, Sendable {
        /// 開始した区間の番号です。
        let segmentOrdinal: Int
        /// 次に記録する欠損の番号です。
        let nextGapOrdinal: Int
    }

    /// 連続取得区間を保存する境界です。
    private let segmentRepository: any ConnectionSessionSegmentRepository
    /// 欠損を保存する境界です。
    private let gapRepository: any ConnectionSessionGapRepository

    /// 区間と欠損の保存先を固定します。
    ///
    /// 責務: 区間開始に使う保存先を注入します。
    /// - Parameters:
    ///   - segmentRepository: 連続取得区間を保存する境界。
    ///   - gapRepository: 欠損を保存する境界。
    init(
        segmentRepository: any ConnectionSessionSegmentRepository,
        gapRepository: any ConnectionSessionGapRepository
    ) {
        self.segmentRepository = segmentRepository
        self.gapRepository = gapRepository
    }

    /// 保存済みの区間の続きとして新しい区間を開始します。
    ///
    /// 責務: 既存の未終了区間を閉じ、次の番号で未終了の区間を保存し、プロセス復帰の欠損を閉じて
    /// 次の欠損番号を求めます。
    /// - Parameters:
    ///   - sessionID: 区間を所有する接続セッション。
    ///   - firstSequence: 新しい区間の最初の行へ割り当てる記録順序。
    ///   - startedAt: 区間を開始する実時間。
    ///   - monotonicAnchorNanoseconds: `startedAt` と同時に読んだ単調時計の値。
    /// - Returns: 開始した区間の番号と次の欠損番号。
    /// - Throws: 区間・欠損の読取または保存に失敗した場合の保存先エラー。
    func open(
        for sessionID: ConnectionSessionID,
        firstSequence: Int64,
        startedAt: Date,
        monotonicAnchorNanoseconds: UInt64
    ) throws -> Opened {
        let existing = try segmentRepository.segments(for: sessionID)
        let gaps = try gapRepository.gaps(for: sessionID)
        if let last = existing.last, last.endedAt == nil {
            let lastSequence = firstSequence - 1
            try segmentRepository.finishSegment(
                ordinal: last.segmentOrdinal,
                for: sessionID,
                endedAt: max(startedAt, last.startedAt),
                reason: .linkLost,
                lastSequence: lastSequence >= last.firstSequence ? lastSequence : nil
            )
        }
        let ordinal = (existing.last?.segmentOrdinal ?? -1) + 1
        let relaunchGap = gaps.last.flatMap { $0.endedAt == nil && $0.cause == .processTerminated ? $0 : nil }
        try segmentRepository.beginSegment(
            ConnectionSessionSegment(
                segmentOrdinal: ordinal,
                startReason: startReason(ordinal: ordinal, relaunchGap: relaunchGap),
                acquisitionMode: .pidPolling,
                startedAt: startedAt,
                monotonicAnchorNanoseconds: monotonicAnchorNanoseconds,
                firstSequence: firstSequence
            ),
            for: sessionID
        )
        if let relaunchGap {
            try gapRepository.finishGap(
                ordinal: relaunchGap.gapOrdinal,
                for: sessionID,
                endedAt: max(startedAt, relaunchGap.startedAt),
                followingSegmentOrdinal: ordinal
            )
        }
        return Opened(segmentOrdinal: ordinal, nextGapOrdinal: (gaps.last?.gapOrdinal ?? -1) + 1)
    }

    /// 新しい区間の開始理由を決めます。
    ///
    /// 責務: 最初の区間は `initial`、プロセス復帰の欠損が残る場合は `processRelaunched`、それ以外は `reconnected` とします。
    /// - Parameters:
    ///   - ordinal: 新しい区間の番号。
    ///   - relaunchGap: 閉じていないプロセス終了の欠損。
    /// - Returns: 新しい区間の開始理由。
    private func startReason(ordinal: Int, relaunchGap: ConnectionSessionGap?) -> ConnectionSessionSegmentStartReason {
        if ordinal == 0 { return .initial }
        return relaunchGap == nil ? .reconnected : .processRelaunched
    }
}
