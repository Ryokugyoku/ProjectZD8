import Foundation

/// 取得開始時にセッションの次の連続取得区間を開始し、欠損番号の続きを求めます。
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
    /// 責務: 既存の未終了区間を閉じ、次の番号で未終了の区間を保存し、次の欠損番号を求めます。
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
        try segmentRepository.beginSegment(
            ConnectionSessionSegment(
                segmentOrdinal: ordinal,
                startReason: ordinal == 0 ? .initial : .reconnected,
                acquisitionMode: .pidPolling,
                startedAt: startedAt,
                monotonicAnchorNanoseconds: monotonicAnchorNanoseconds,
                firstSequence: firstSequence
            ),
            for: sessionID
        )
        let nextGapOrdinal = (try gapRepository.gaps(for: sessionID).last?.gapOrdinal ?? -1) + 1
        return Opened(segmentOrdinal: ordinal, nextGapOrdinal: nextGapOrdinal)
    }
}
