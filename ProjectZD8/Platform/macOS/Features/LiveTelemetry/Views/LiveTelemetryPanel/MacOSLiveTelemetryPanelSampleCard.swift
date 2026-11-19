#if os(macOS)
import SwiftUI

/// 補助PIDの名称と単位付き現在値を示す小型カードです。説明ボタンからPID説明のポップオーバーを開きます。
struct MacOSLiveTelemetryPanelSampleCard: View {
    /// 表示するPIDサンプルです。
    let sample: OBDPIDSample
    /// 車種専用PIDかどうかです。単位の色を変えます。
    let isVehicleSpecific: Bool
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

    /// 名称と説明ボタン、現在値と単位を縦に並べます。
    ///
    /// 責務: 1件のPIDサンプルを説明導線付きの小型カードへ描画します。
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 17 * scale, style: .continuous)
        VStack(alignment: .leading, spacing: 10 * scale) {
            HStack {
                Text(LocalizedStringKey(sample.nameKey))
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 4 * scale)
                helpButton
            }
            HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                Text(verbatim: LiveTelemetrySampleFormatter().detailValueText(sample, locale: locale))
                    .font(.system(size: 25 * scale, weight: .bold, design: .rounded).monospacedDigit())
                Text(verbatim: sample.unit)
                    .font(.system(size: 10 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isVehicleSpecific ? Color.cyan : Color.accentColor)
            }
        }
        .padding(16 * scale)
        .frame(maxWidth: .infinity, minHeight: 96 * scale, alignment: .leading)
        .background(.regularMaterial, in: shape)
        .overlay { shape.stroke(Color.primary.opacity(0.07)) }
    }

    /// PID説明のポップオーバーを開くボタンです。
    private var helpButton: some View {
        Button(action: onHelpRequested) {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
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
}
#endif
