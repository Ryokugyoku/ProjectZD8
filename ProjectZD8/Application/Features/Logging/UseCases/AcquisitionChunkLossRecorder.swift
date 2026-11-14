/// commitできずに破棄したチャンクの区間を欠損として記録します。
///
/// 段階3ではチャンクは1つの連続取得区間の中に収まるため、欠損の前後区間はどちらも
/// チャンクのRawが属する区間(Rawが無い場合は現在の区間)になります。
nonisolated struct AcquisitionChunkLossRecorder: Sendable {
    /// 欠損を保存する境界です。
    private let gapRepository: any ConnectionSessionGapRepository

    /// 欠損の保存先を固定します。
    ///
    /// 責務: 失われたチャンクの記録先を注入します。
    /// - Parameter gapRepository: 欠損を保存する境界。
    init(gapRepository: any ConnectionSessionGapRepository) {
        self.gapRepository = gapRepository
    }

    /// 破棄したチャンクを保存側の欠損として記録します。
    ///
    /// 責務: チャンクの最初と最後の実時刻を、原因 `bufferOverflow` の終了済み欠損へ変換して保存します。
    /// - Parameters:
    ///   - pending: commitに失敗して破棄したチャンク。
    ///   - gapOrdinal: 欠損へ割り当てる番号。
    ///   - currentSegmentOrdinal: チャンクにRawが無い場合に使う現在の区間番号。
    ///   - sessionID: 欠損を所有する接続セッション。
    /// - Throws: 欠損を保存できない場合の保存先エラー。
    func recordLoss(
        of pending: AcquisitionPendingChunk,
        gapOrdinal: Int,
        currentSegmentOrdinal: Int,
        for sessionID: ConnectionSessionID
    ) throws {
        let gap = ConnectionSessionGap(
            gapOrdinal: gapOrdinal,
            precedingSegmentOrdinal: pending.firstSegmentOrdinal ?? currentSegmentOrdinal,
            followingSegmentOrdinal: pending.lastSegmentOrdinal ?? currentSegmentOrdinal,
            startedAt: pending.firstObservedAt,
            endedAt: pending.lastObservedAt,
            cause: .bufferOverflow
        )
        try gapRepository.saveGap(gap, for: sessionID)
    }
}
