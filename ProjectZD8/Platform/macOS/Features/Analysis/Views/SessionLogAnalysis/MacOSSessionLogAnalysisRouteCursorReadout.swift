#if os(macOS)
import SwiftUI

/// macOS の解析の「ルート」の表示で、グラフで選んだ時刻・指標の値・標高を読み出して並べます。
struct MacOSSessionLogAnalysisRouteCursorReadout: View {
    /// グラフで選んだ時刻の読み出しです。
    let cursor: RouteAnalysisCursor
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 時刻の文字と位置が無い時の案内の整形です。
    private let formatter = RouteAnalysisCursorReadoutFormatter()

    /// 読み出しを描画します。
    ///
    /// 責務: 時刻・指標の値・標高を、ある項目だけアイコン付きで横に並べ、位置が無い時はその案内を添えます。
    var body: some View {
        HStack(spacing: MacOSRouteAnalysisMetrics.readoutSpacing * scale) {
            Label(formatter.timeText(for: cursor.date), systemImage: "clock")
            if let metricValueText = cursor.metricValueText {
                Label(metricValueText, systemImage: "gauge.with.dots.needle.50percent")
            }
            if let elevationText = cursor.elevationText {
                Label(elevationText, systemImage: "mountain.2")
            }
            if let messageKey = formatter.positionMessageKey(for: cursor) {
                Text(LocalizedStringKey(messageKey))
                    .font(.system(size: MacOSRouteAnalysisMetrics.noticeFontSize * scale))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: MacOSRouteAnalysisMetrics.readoutFontSize * scale, weight: .semibold).monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
#endif
