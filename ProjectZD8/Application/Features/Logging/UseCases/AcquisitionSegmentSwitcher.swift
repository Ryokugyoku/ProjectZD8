import Foundation

/// 取得中の連続取得区間を閉じ、欠損を挟んで次の区間を開く保存手順です。
///
/// 欠損は直後の区間への外部キーを持つため、未終了の欠損(直後の区間なし)を先に保存し、
/// 次の区間を開始してから欠損へ終了時刻と直後の区間を確定します。保存の順序は
/// 「区間の終了 → 欠損 → 次の区間」になります。
nonisolated struct AcquisitionSegmentSwitcher: Sendable {
    /// 区間の間に挟む欠損の入力です。
    struct Gap: Equatable, Sendable {
        /// 欠損へ割り当てる番号です。
        let ordinal: Int
        /// 欠損が始まった実時間(最後に受信した時刻)です。
        let startedAt: Date
        /// 欠損が生じた直接原因です。
        let cause: ConnectionSessionGapCause
    }

    /// 連続取得区間を保存する境界です。
    private let segmentRepository: any ConnectionSessionSegmentRepository
    /// 欠損を保存する境界です。
    private let gapRepository: any ConnectionSessionGapRepository

    /// 区間と欠損の保存先を固定します。
    ///
    /// 責務: 区間の切替に使う保存先を注入します。
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

    /// 現在の区間を閉じます。
    ///
    /// 責務: 区間の開始より前にならない終了時刻と、区間内の最後の記録順序で区間を終了します。
    /// - Parameters:
    ///   - session: 閉じる区間を持つ記録状態。
    ///   - endedAt: 区間を閉じる実時間の候補。区間開始より前なら区間開始に揃えます。
    ///   - reason: 区間が終わった直接原因。
    ///   - lastCommittedSequence: セッションで最後にcommitした記録順序。
    /// - Throws: 区間を終了できない場合の保存先エラー。
    func close(
        _ session: AcquisitionRecordingSession,
        endedAt: Date,
        reason: ConnectionSessionSegmentEndReason,
        lastCommittedSequence: Int64?
    ) throws {
        try segmentRepository.finishSegment(
            ordinal: session.segmentOrdinal,
            for: session.sessionID,
            endedAt: max(endedAt, session.segmentStartedAt),
            reason: reason,
            lastSequence: lastCommittedSequence.flatMap { $0 >= session.segmentFirstSequence ? $0 : nil }
        )
    }

    /// 直前の区間の続きとして次の区間を開きます。
    ///
    /// 責務: 欠損がある場合は未終了で保存し、次の区間を開始してから欠損を閉じます。
    /// - Parameters:
    ///   - session: 直前の区間を閉じた記録状態。
    ///   - startReason: 次の区間が始まった直接原因。
    ///   - startedAt: 次の区間を開始する実時間。
    ///   - anchorNanoseconds: `startedAt` と同時に読んだ単調時計の値。
    ///   - firstSequence: 次の区間の最初の行へ割り当てる記録順序。
    ///   - gap: 区間の間に挟む欠損。欠損を記録しない切替では `nil`。
    /// - Returns: 開いた区間の番号。
    /// - Throws: 欠損または区間を保存できない場合の保存先エラー。
    func open(
        after session: AcquisitionRecordingSession,
        startReason: ConnectionSessionSegmentStartReason,
        startedAt: Date,
        anchorNanoseconds: UInt64,
        firstSequence: Int64,
        gap: Gap?
    ) throws -> Int {
        let ordinal = session.segmentOrdinal + 1
        if let gap {
            try gapRepository.saveGap(
                ConnectionSessionGap(
                    gapOrdinal: gap.ordinal,
                    precedingSegmentOrdinal: session.segmentOrdinal,
                    startedAt: min(gap.startedAt, startedAt),
                    cause: gap.cause
                ),
                for: session.sessionID
            )
        }
        try segmentRepository.beginSegment(
            ConnectionSessionSegment(
                segmentOrdinal: ordinal,
                startReason: startReason,
                acquisitionMode: .pidPolling,
                startedAt: startedAt,
                monotonicAnchorNanoseconds: anchorNanoseconds,
                firstSequence: firstSequence
            ),
            for: session.sessionID
        )
        if let gap {
            try gapRepository.finishGap(
                ordinal: gap.ordinal,
                for: session.sessionID,
                endedAt: startedAt,
                followingSegmentOrdinal: ordinal
            )
        }
        return ordinal
    }
}
