#if os(iOS)
import SwiftUI

/// 主要PIDの現在値を運転中でも読める大きさで示すカードです。押すとPID説明を開きます。
struct IOSLiveTelemetryPanelPrimaryCard: View {
    /// 表示する主要PIDサンプルです。
    let sample: OBDPIDSample
    /// PID説明の表示要求を通知するクロージャです。
    let onHelp: () -> Void

    /// 数値の整形に使う現在のロケールです。
    @Environment(\.locale) private var locale

    /// 記号、大きな現在値、単位、名称を縦に並べます。
    ///
    /// 責務: 1件の主要PIDサンプルを説明導線付きの大型カードへ描画します。
    var body: some View {
        let formatter = LiveTelemetrySampleFormatter()
        Button(action: onHelp) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: LiveTelemetrySampleSymbols.primarySymbol(for: sample.request))
                        .foregroundStyle(.cyan)
                    Spacer()
                    Image(systemName: "info.circle").foregroundStyle(.tertiary)
                }
                Text(verbatim: formatter.primaryValueText(sample, locale: locale))
                    .font(.system(size: IOSLiveTelemetryPanelMetrics.primaryValueFontSize, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(IOSLiveTelemetryPanelMetrics.primaryValueMinimumScale)
                    .lineLimit(1)
                Text(verbatim: sample.unit)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.cyan)
                Text(LocalizedStringKey(sample.nameKey))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(IOSLiveTelemetryPanelMetrics.primaryCardPadding)
            .frame(maxWidth: .infinity, minHeight: IOSLiveTelemetryPanelMetrics.primaryCardMinHeight, alignment: .leading)
            .background(background, in: shape)
            .overlay { shape.stroke(Color.cyan.opacity(IOSLiveTelemetryPanelMetrics.primaryCardStrokeOpacity)) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(sample.nameKey)))
        .accessibilityValue(Text(verbatim: formatter.detailValueWithUnitText(sample, locale: locale)))
    }

    /// カードの外形です。
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: IOSLiveTelemetryPanelMetrics.primaryCardCornerRadius, style: .continuous)
    }

    /// シアンから淡い前景色へ流れるカードの背景です。
    private var background: LinearGradient {
        LinearGradient(
            colors: [
                Color.cyan.opacity(IOSLiveTelemetryPanelMetrics.primaryCardTintOpacity),
                Color.primary.opacity(0.035),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
#endif
