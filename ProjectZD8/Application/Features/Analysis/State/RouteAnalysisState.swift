import Foundation

/// 解析の走行ルートの表示(色分け・グラフ・連動)を画面へ公開する状態です。
nonisolated struct RouteAnalysisState: Equatable, Sendable {
    /// 表示中のセッションの ID です。表示していない時は `nil` です。
    var sessionID: ConnectionSessionID?
    /// 読み込みの段階です。
    var phase: RouteAnalysisLoadPhase = .idle
    /// 色分けの選択肢です。
    var colorSourceOptions: [RouteAnalysisColorSourceOption] = []
    /// 選んでいる色分けの元です。
    var selectedColorSource: RouteAnalysisColorSource?
    /// 地図に描く内容です。
    var layers: RouteAnalysisMapLayers?
    /// 注記のローカライズキー(表示順)です。
    var noticeKeys: [String] = []
    /// 指標のグラフです。
    var metricChart: RouteAnalysisChartSeries?
    /// 標高のグラフです。
    var elevationChart: RouteAnalysisChartSeries?
    /// グラフで選んだ時刻の読み出しです。
    var cursor: RouteAnalysisCursor?
    /// グラフで強調する時刻の範囲です。
    var highlightedTimeRanges: [ClosedRange<Date>] = []
}
