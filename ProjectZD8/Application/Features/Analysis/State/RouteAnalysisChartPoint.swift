import Foundation

/// 解析のルートのグラフの1点です。
nonisolated struct RouteAnalysisChartPoint: Identifiable, Equatable, Sendable {
    /// グラフの中で一意な番号です。
    let id: Int
    /// 横軸の時刻です。
    let date: Date
    /// 縦軸の値です。
    let value: Double
    /// 線の切れ目ごとに分けた系列の番号です。
    let lineID: Int
}
