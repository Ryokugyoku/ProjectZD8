import Foundation

/// 点から線(点の列)の1つの線分までの近さです。
nonisolated struct GeoPolylineProximity: Equatable, Sendable {
    /// 線分の番号(線分 i は点 i と点 i+1 を結ぶ)です。
    let segmentIndex: Int
    /// 点から線分上の最近点までの距離(m)です。
    let distanceMeters: Double
    /// 線分上の最近点の位置(始点0・終点1。0...1 に切り詰めた値)です。
    let fraction: Double
    /// 線分の始点から終点へ向かう方位(度、0..<360、北0・時計回り)です。
    let segmentBearingDegrees: Double
    /// 線分の長さ(m)です。
    let segmentLengthMeters: Double
    /// 線の始点から最近点までの線に沿った距離(m)です。
    let alongMetersFromStart: Double
}
