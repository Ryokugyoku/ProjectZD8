#if os(iOS)
import SwiftUI

/// 補助PIDの名称と単位付き現在値を示す小型カードです。押すとPID説明を開きます。
struct IOSLiveTelemetryPanelCompactCard: View {
    /// 表示するPIDサンプルです。
    let sample: OBDPIDSample
    /// 車種専用PIDかどうかです。単位の色を変えます。
    let isVehicleSpecific: Bool
    /// PID説明の表示要求を通知するクロージャです。
    let onHelp: () -> Void

    /// 数値の整形に使う現在のロケールです。
    @Environment(\.locale) private var locale

    /// 名称、説明の印、現在値、単位を描画します。
    ///
    /// 責務: 1件のPIDサンプルを説明導線付きの小型カードへ描画します。
    var body: some View {
        let formatter = LiveTelemetrySampleFormatter()
        Button(action: onHelp) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(LocalizedStringKey(sample.nameKey))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Image(systemName: "info.circle").foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: formatter.detailValueText(sample, locale: locale))
                        .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                    Text(verbatim: sample.unit)
                        .font(.caption.monospaced())
                        .foregroundStyle(isVehicleSpecific ? Color.cyan : Color.accentColor)
                }
            }
            .padding(IOSLiveTelemetryPanelMetrics.compactCardPadding)
            .frame(maxWidth: .infinity, minHeight: IOSLiveTelemetryPanelMetrics.compactCardMinHeight, alignment: .leading)
            .background(
                Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: IOSLiveTelemetryPanelMetrics.compactCardCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(sample.nameKey)))
        .accessibilityValue(Text(verbatim: formatter.detailValueWithUnitText(sample, locale: locale)))
    }
}
#endif
