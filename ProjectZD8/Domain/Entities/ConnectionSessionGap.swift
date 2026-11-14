import Foundation

/// 連続取得区間の間でデータを取得できなかった1件の空白です。
nonisolated struct ConnectionSessionGap: Equatable, Sendable {
    /// セッション内で0から始まる欠損番号です。
    let gapOrdinal: Int
    /// 空白の直前に終わった区間の番号です。
    let precedingSegmentOrdinal: Int
    /// 空白の直後に始まった区間の番号です。取得を再開していない場合は `nil`。
    let followingSegmentOrdinal: Int?
    /// 空白が始まった実時間です。永続化ではmicrosecond精度へ丸めます。
    let startedAt: Date
    /// 空白が終わった実時間です。未終了の場合は `nil`。
    let endedAt: Date?
    /// 空白が生じた直接原因です。
    let cause: ConnectionSessionGapCause

    /// 取得の空白を生成します。
    ///
    /// 責務: 1件の空白の前後区間、時間範囲、原因をセッション内の欠損番号へ固定します。
    /// - Parameters:
    ///   - gapOrdinal: セッション内で0から始まる欠損番号。
    ///   - precedingSegmentOrdinal: 空白の直前に終わった区間の番号。
    ///   - followingSegmentOrdinal: 空白の直後に始まった区間の番号。再開していない場合は `nil`。
    ///   - startedAt: 空白が始まった実時間。
    ///   - endedAt: 空白が終わった実時間。未終了の場合は `nil`。
    ///   - cause: 空白が生じた直接原因。
    init(
        gapOrdinal: Int,
        precedingSegmentOrdinal: Int,
        followingSegmentOrdinal: Int? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        cause: ConnectionSessionGapCause
    ) {
        self.gapOrdinal = gapOrdinal
        self.precedingSegmentOrdinal = precedingSegmentOrdinal
        self.followingSegmentOrdinal = followingSegmentOrdinal
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.cause = cause
    }
}
