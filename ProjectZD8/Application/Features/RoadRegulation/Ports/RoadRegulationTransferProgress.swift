import Foundation

/// ZIP のダウンロードの進み具合です。
nonisolated struct RoadRegulationTransferProgress: Equatable, Sendable {
    /// 受け取ったバイト数。
    let receivedBytes: Int64
    /// 予定のバイト数。分からなければ `nil`。
    let expectedBytes: Int64?
}
