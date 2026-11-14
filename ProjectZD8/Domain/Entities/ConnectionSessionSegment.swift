import Foundation

/// 接続セッション内で途切れずに取得できた1件の連続取得区間です。
nonisolated struct ConnectionSessionSegment: Equatable, Sendable {
    /// セッション内で0から始まる区間番号です。
    let segmentOrdinal: Int
    /// 区間が始まった直接原因です。
    let startReason: ConnectionSessionSegmentStartReason
    /// 区間がデータを取得した方式です。
    let acquisitionMode: ConnectionSessionAcquisitionMode
    /// 区間を開始した実時間です。永続化ではmicrosecond精度へ丸めます。
    let startedAt: Date
    /// `startedAt` と同時に採取した単調時計のナノ秒値です。
    let monotonicAnchorNanoseconds: UInt64
    /// 区間の最初の行へ割り当てる記録順序です。
    let firstSequence: Int64
    /// 区間を終了した実時間です。未終了の場合は `nil`。
    let endedAt: Date?
    /// 区間が終わった直接原因です。未終了の場合は `nil`。
    let endReason: ConnectionSessionSegmentEndReason?
    /// 区間の最後の行の記録順序です。未終了または行が1件もない場合は `nil`。
    let lastSequence: Int64?

    /// 連続取得区間を生成します。
    ///
    /// 責務: 1件の区間の開始情報と任意の終了情報をセッション内の区間番号へ固定します。
    /// - Parameters:
    ///   - segmentOrdinal: セッション内で0から始まる区間番号。
    ///   - startReason: 区間が始まった直接原因。
    ///   - acquisitionMode: 区間の取得方式。
    ///   - startedAt: 区間を開始した実時間。
    ///   - monotonicAnchorNanoseconds: `startedAt` と同時に採取した単調時計のナノ秒値。
    ///   - firstSequence: 区間の最初の行へ割り当てる記録順序。
    ///   - endedAt: 区間を終了した実時間。未終了の場合は `nil`。
    ///   - endReason: 区間が終わった直接原因。未終了の場合は `nil`。
    ///   - lastSequence: 区間の最後の行の記録順序。未終了または行がない場合は `nil`。
    init(
        segmentOrdinal: Int,
        startReason: ConnectionSessionSegmentStartReason,
        acquisitionMode: ConnectionSessionAcquisitionMode,
        startedAt: Date,
        monotonicAnchorNanoseconds: UInt64,
        firstSequence: Int64,
        endedAt: Date? = nil,
        endReason: ConnectionSessionSegmentEndReason? = nil,
        lastSequence: Int64? = nil
    ) {
        self.segmentOrdinal = segmentOrdinal
        self.startReason = startReason
        self.acquisitionMode = acquisitionMode
        self.startedAt = startedAt
        self.monotonicAnchorNanoseconds = monotonicAnchorNanoseconds
        self.firstSequence = firstSequence
        self.endedAt = endedAt
        self.endReason = endReason
        self.lastSequence = lastSequence
    }
}
