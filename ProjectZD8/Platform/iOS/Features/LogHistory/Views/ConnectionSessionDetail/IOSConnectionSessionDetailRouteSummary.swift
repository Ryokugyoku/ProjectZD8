#if os(iOS)
import SwiftUI

/// iPhone のセッション詳細で、走行ルートの長さ・記録できた時間・記録できた割合を横に並べて表示します。
struct IOSConnectionSessionDetailRouteSummary: View {
    /// 整形済みの要約の文字列です。
    let summary: DrivingRouteSummaryText

    /// 要約の3項目を等幅で並べます。
    ///
    /// 責務: 整形済みの文字列を、それぞれの見出しと組にして描画します。
    var body: some View {
        HStack(alignment: .top, spacing: IOSDrivingRouteDetailMetrics.summarySpacing) {
            item(value: summary.lengthText, titleKey: "history.route.summary.length")
            item(value: summary.recordedDurationText, titleKey: "history.route.summary.recorded_duration")
            item(value: summary.coverageText, titleKey: "history.route.summary.coverage")
        }
    }

    /// 要約の1項目を描画します。
    ///
    /// 責務: 値を強調し、その下に見出しを添えた1項目を作ります。
    /// - Parameters:
    ///   - value: 整形済みの値。
    ///   - titleKey: 見出しのローカライズキー。
    /// - Returns: 1項目の View。
    private func item(value: String, titleKey: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: IOSDrivingRouteDetailMetrics.summaryItemSpacing) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(titleKey)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
#endif
