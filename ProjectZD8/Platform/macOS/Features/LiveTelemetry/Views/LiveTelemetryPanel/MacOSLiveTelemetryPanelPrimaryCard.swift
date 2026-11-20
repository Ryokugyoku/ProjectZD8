#if os(macOS)
import SwiftUI

/// 主要PIDの現在値を大きく示すカードです。説明ボタンからPID説明のポップオーバーを開きます。
struct MacOSLiveTelemetryPanelPrimaryCard: View {
    /// 表示する主要PIDサンプルです。
    let sample: OBDPIDSample
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// このカードのPID説明を表示中かどうかです。
    let isShowingHelp: Bool
    /// PID説明の表示要求を通知するクロージャです。
    let onHelpRequested: () -> Void
    /// PID説明を閉じたことを通知するクロージャです。
    let onHelpDismissed: () -> Void

    /// 数値の整形に使う現在のロケールです。
    @Environment(\.locale) private var locale

    /// 記号、名称、大きな現在値と単位、説明ボタンを横に並べます。
    ///
    /// 責務: 1件の主要PIDサンプルを説明導線付きの大型カードへ描画します。
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
        HStack(spacing: 18 * scale) {
            symbol
            valueStack
            Spacer(minLength: 8 * scale)
            helpButton
        }
        .padding(20 * scale)
        .frame(maxWidth: .infinity, minHeight: 126 * scale, alignment: .leading)
        .background(background, in: shape)
        .overlay { shape.stroke(Color.cyan.opacity(0.2)) }
    }

    /// 回転数・車速・その他を区別する記号です。
    private var symbol: some View {
        Image(systemName: LiveTelemetrySampleSymbols.primarySymbol(for: sample.request))
            .font(.system(size: 27 * scale, weight: .semibold))
            .foregroundStyle(.cyan)
            .frame(width: 58 * scale, height: 58 * scale)
            .background(Color.cyan.opacity(0.13), in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
            .accessibilityHidden(true)
    }

    /// 名称と、大きな現在値・単位です。
    private var valueStack: some View {
        VStack(alignment: .leading, spacing: 5 * scale) {
            Text(LocalizedStringKey(sample.nameKey))
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 7 * scale) {
                Text(verbatim: LiveTelemetrySampleFormatter().primaryValueText(sample, locale: locale))
                    .font(.system(size: 40 * scale, weight: .bold, design: .rounded).monospacedDigit())
                Text(verbatim: sample.unit)
                    .font(.system(size: 11 * scale, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
        }
    }

    /// PID説明のポップオーバーを開くボタンです。
    private var helpButton: some View {
        Button(action: onHelpRequested) {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .popover(isPresented: helpBinding) {
            MacOSLiveTelemetryPanelHelpPopover(content: LiveTelemetryPIDHelpContent(sample: sample))
        }
        .accessibilityLabel("telemetry.help.open")
    }

    /// ポップオーバーの表示状態です。閉じた時だけ通知します。
    private var helpBinding: Binding<Bool> {
        Binding(get: { isShowingHelp }, set: { isPresented in
            if !isPresented { onHelpDismissed() }
        })
    }

    /// シアンから淡い前景色へ流れるカードの背景です。
    private var background: LinearGradient {
        LinearGradient(
            colors: [Color.cyan.opacity(0.13), Color.primary.opacity(0.035)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
#endif
