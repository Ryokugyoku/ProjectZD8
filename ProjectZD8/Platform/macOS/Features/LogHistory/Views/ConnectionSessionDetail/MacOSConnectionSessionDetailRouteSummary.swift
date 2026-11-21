#if os(macOS)
import SwiftUI

/// macOS のセッション詳細で、走行ルートの要約(長さ・記録できた時間・記録できた割合)を並べます。
struct MacOSConnectionSessionDetailRouteSummary: View {
    /// 整形済みの要約の文字列です。
    let summary: DrivingRouteSummaryText
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 項目を横に並べる時に `true`、縦に並べる時に `false` です。
    let isHorizontal: Bool

    /// 要約の3項目を描画します。
    ///
    /// 責務: 3つの項目を、指定された向きに見出しと値の組で並べます。
    var body: some View {
        let spacing = MacOSDrivingRouteDetailMetrics.summarySpacing * scale
        let layout = isHorizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: spacing * 2))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        layout {
            item(titleKey: "history.route.summary.length", value: summary.lengthText)
            item(titleKey: "history.route.summary.recorded_duration", value: summary.recordedDurationText)
            item(titleKey: "history.route.summary.coverage", value: summary.coverageText)
        }
    }

    /// 要約の1項目を描画します。
    ///
    /// 責務: 項目の見出しと値を縦に重ね、読み上げでは1つの要素にまとめます。
    /// - Parameters:
    ///   - titleKey: 見出しのローカライズキー。
    ///   - value: 整形済みの値。
    /// - Returns: 1項目の View。
    private func item(titleKey: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: MacOSDrivingRouteDetailMetrics.summaryLabelSpacing * scale) {
            Text(titleKey)
                .font(.system(size: MacOSDrivingRouteDetailMetrics.summaryLabelFontSize * scale, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.system(size: MacOSDrivingRouteDetailMetrics.summaryValueFontSize * scale, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
