#if os(iOS)
import SwiftUI

/// iPhone の解析画面の「ルート」の表示です。色分けした走行ルートの地図と、指標・標高のグラフを片方向に連動させます。
struct IOSSessionLogAnalysisRouteSection: View {
    /// 表示するセッションです。
    let session: ConnectionSession
    /// 走行ルートの表示状態です。
    let state: RouteAnalysisState
    /// 走行ルートの型付き操作を送出します。
    let send: (RouteAnalysisAction) -> Void
    /// 状態から地図の場所に出す内容を決める判定です。
    private let contentPolicy = RouteAnalysisSectionContentPolicy()

    /// 見出しと、内容に応じた地図・グラフ、または状態の表示をカードとして描画します。
    ///
    /// 責務: 最初に表示された時にセッションの表示を送出し、地図を描ける時は地図とグラフを、それ以外は状態の表示を置きます。
    var body: some View {
        IOSSessionLogAnalysisCard(title: "analysis.route.title", subtitle: "analysis.route.subtitle") {
            let content = contentPolicy.content(for: state)
            if case let .ready(layers) = content {
                ready(layers)
            } else {
                IOSSessionLogAnalysisRouteStatus(content: content) { send(.retryRequested) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-analysis-route-section")
        .onAppear { send(.sessionShown(session)) }
    }

    /// 地図を描ける時の中身を作ります。
    ///
    /// 責務: 色分けの切替・地図・凡例・注記・読み出し・グラフを縦に並べます。
    /// - Parameter layers: 地図に描く内容。
    /// - Returns: 中身の View。
    private func ready(_ layers: RouteAnalysisMapLayers) -> some View {
        VStack(alignment: .leading, spacing: IOSRouteAnalysisMetrics.cardSpacing) {
            let menuContent = RouteAnalysisColorSourceMenuContent(options: state.colorSourceOptions, selectedSource: state.selectedColorSource)
            if menuContent.isVisible {
                IOSSessionLogAnalysisRouteColorSourceMenu(content: menuContent) { send(.colorSourceSelected($0)) }
            }
            IOSSessionLogAnalysisRouteMap(layers: layers, focus: state.cursor?.coordinate)
            IOSSessionLogAnalysisRouteLegend(entries: layers.legend)
            notices
            if let cursor = state.cursor {
                IOSSessionLogAnalysisRouteCursorReadout(cursor: cursor)
            }
            charts
        }
    }

    /// 注記を情報のアイコン付きの小さな文字で並べます。
    private var notices: some View {
        VStack(alignment: .leading, spacing: IOSRouteAnalysisMetrics.noticeSpacing) {
            ForEach(Array(state.noticeKeys.enumerated()), id: \.offset) { _, key in
                Label(LocalizedStringKey(key), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 指標のグラフと標高のグラフです。
    ///
    /// 責務: 指標のグラフはある時だけ置き、標高はグラフか「表示できる地点がない」案内を置きます。どちらも同じ時刻の選択を送出します。
    @ViewBuilder private var charts: some View {
        if let metricChart = state.metricChart {
            chart(titleKey: "analysis.route.chart.metric_title", subtitleKey: metricChart.titleKey, series: metricChart,
                  height: IOSRouteAnalysisMetrics.metricChartHeight, identifier: "ios-analysis-route-metric-chart")
        }
        if let elevationChart = state.elevationChart {
            chart(titleKey: elevationChart.titleKey, subtitleKey: "analysis.route.elevation.subtitle", series: elevationChart,
                  height: IOSRouteAnalysisMetrics.elevationChartHeight, identifier: "ios-analysis-route-elevation-chart")
        } else {
            Label("analysis.route.elevation.unavailable", systemImage: "mountain.2")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 時刻の選択を送出するグラフを作ります。
    ///
    /// 責務: 強調の範囲と選んだ時刻を状態から渡し、なぞった時刻を `timeSelected` として送出するグラフを作ります。
    /// - Parameters:
    ///   - titleKey: 見出しのローカライズキー。
    ///   - subtitleKey: 説明のローカライズキー。
    ///   - series: 描く系列。
    ///   - height: グラフの高さ。
    ///   - identifier: UI テストで使う識別子。
    /// - Returns: グラフの View。
    private func chart(titleKey: String, subtitleKey: String, series: RouteAnalysisChartSeries, height: CGFloat, identifier: String) -> some View {
        IOSSessionLogAnalysisRouteChart(
            titleKey: titleKey,
            subtitleKey: subtitleKey,
            series: series,
            height: height,
            highlightedTimeRanges: state.highlightedTimeRanges,
            selectedDate: state.cursor?.date,
            accessibilityIdentifier: identifier
        ) { send(.timeSelected($0)) }
    }
}
#endif
