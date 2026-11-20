import Foundation

/// 解析の時間の軸に並べた走行ルートの1点です。
nonisolated struct RouteAnalysisTimelinePoint: Equatable, Sendable {
    /// 走行ルートの点の列での位置です。
    let index: Int
    /// 元のサンプルのセッション内の連番です。
    let sequence: Int64
    /// 点が属する区間の番号です。
    let segmentIndex: Int
    /// 点が属する区間の精度の段階です。
    let precision: DrivingRoutePrecision
    /// 位置の座標です。
    let coordinate: GeoCoordinate
    /// 時計の選び方で揃えた時刻です。
    let date: Date
    /// 標高(海抜、m)です。垂直精度で除いた時は `nil` です。
    let altitudeMeters: Double?
}
