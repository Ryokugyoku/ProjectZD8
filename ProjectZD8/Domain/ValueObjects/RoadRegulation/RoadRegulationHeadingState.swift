import Foundation

/// 進む向きの推定の状態です。
nonisolated struct RoadRegulationHeadingState: Equatable, Sendable {
    /// まだ向きも基準点も無い状態です。
    static let initial = RoadRegulationHeadingState(headingDegrees: nil, anchor: nil)

    /// 推定した向き(度、北0・時計回り)。分からなければ `nil`。
    let headingDegrees: Double?
    /// 移動から向きを求める時の基準点。
    let anchor: GeoCoordinate?
}
