#if os(macOS)
import SwiftUI

/// macOSのセッション解析の概要表示です。セッション時間、距離、速度帯、回転域、部品・系統を一覧化します。
struct MacOSSessionLogAnalysisOverview: View {
    /// 表示するセッションです。
    let session: ConnectionSession
    /// 車速・回転数から求めた走行サマリーです。
    let summary: SessionPerformanceSummary
    /// 部品・系統別の観察結果です。
    let componentInsights: [SessionComponentInsight]
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// 解析画面の文字列整形です。
    private let formatter = SessionLogAnalysisTextFormatter()

    /// 走行サマリー、2つのランキング、部品・系統カードを縦に並べます。
    ///
    /// 責務: 1件のセッションの概要を、走行サマリーとランキングの格子と部品カードの並びへ変換します。
    var body: some View {
        VStack(alignment: .leading, spacing: 16 * metrics.scale) {
            MacOSSessionLogAnalysisCard(title: "analysis.overview.title", subtitle: "analysis.overview.subtitle", metrics: metrics) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190 * metrics.scale), spacing: 12 * metrics.scale)],
                    spacing: 12 * metrics.scale
                ) {
                    overviewMetric(
                        value: formatter.sessionDurationText(session),
                        key: "analysis.overview.session_duration",
                        symbol: "clock"
                    )
                    overviewMetric(
                        value: formatter.movingDurationText(summary),
                        key: "analysis.overview.moving_duration",
                        symbol: "car.side"
                    )
                    overviewMetric(
                        value: formatter.distanceText(session: session, summary: summary),
                        key: LocalizedStringKey(formatter.distanceTitleKey(session)),
                        symbol: "road.lanes"
                    )
                }
                Text("analysis.overview.estimate_note").font(.caption).foregroundStyle(.secondary)
            }
            rankings
            MacOSSessionLogAnalysisComponentCard(insights: componentInsights, metrics: metrics)
        }
    }

    /// 速度帯と回転域のランキングを横に並べる格子です。
    private var rankings: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 320 * metrics.scale), spacing: 14 * metrics.scale)],
            alignment: .leading,
            spacing: 14 * metrics.scale
        ) {
            MacOSSessionLogAnalysisDurationRankingCard(
                title: "analysis.overview.speed_ranking",
                subtitle: "analysis.overview.speed_ranking_note",
                bands: summary.speedBands,
                unitKey: "analysis.overview.speed_band",
                metrics: metrics
            )
            MacOSSessionLogAnalysisDurationRankingCard(
                title: "analysis.overview.rpm_ranking",
                subtitle: "analysis.overview.rpm_ranking_note",
                bands: summary.rpmBands,
                unitKey: "analysis.overview.rpm_band",
                metrics: metrics
            )
        }
    }

    /// 走行サマリーの1件を値、見出し、シンボルで表示します。
    ///
    /// 責務: 1件の表示済み走行集計をmacOS向け小型カードへ変換します。
    /// - Parameters:
    ///   - value: 表示用に整形済みの値。
    ///   - key: 値の意味を示すローカライズキー。
    ///   - symbol: 集計概念を示すSF Symbol。
    /// - Returns: 走行サマリー内の小型カード。
    private func overviewMetric(value: String, key: LocalizedStringKey, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7 * metrics.scale) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(value).font(.system(size: 19 * metrics.scale, weight: .bold, design: .rounded)).monospacedDigit()
            Text(key).font(.system(size: 10 * metrics.scale)).foregroundStyle(.secondary)
        }
        .padding(15 * metrics.scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16 * metrics.scale, style: .continuous))
    }
}
#endif
