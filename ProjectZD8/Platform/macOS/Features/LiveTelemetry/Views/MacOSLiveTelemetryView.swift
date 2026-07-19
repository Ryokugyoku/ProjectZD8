#if os(macOS)
import SwiftUI

/// macOSで検証済み主要PIDの1回読取結果を描画します。
struct MacOSLiveTelemetryView: View {
    /// Applicationが公開するPID読取状態です。
    let state: LiveTelemetryState
    /// 現在設定されているOBD終端です。
    let endpoint: OBDConnectionEndpoint?
    /// PID読取操作の通知先です。
    let send: (LiveTelemetryAction) -> Void
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// PID読取操作、進行、数値、失敗に対応するmacOS表示を提供します。
    ///
    /// 責務: LiveTelemetry状態をmacOS専用の主要PID読取画面へ変換します。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24 * metrics.scale) {
                Text("telemetry.eyebrow")
                    .font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded))
                    .tracking(1.7 * metrics.scale)
                    .foregroundStyle(.tint)
                Text("telemetry.title")
                    .font(.system(size: 32 * metrics.scale, weight: .bold, design: .rounded))
                Text("telemetry.subtitle")
                    .foregroundStyle(.secondary)

                if state.phase == .reading {
                    ProgressView("telemetry.status.reading")
                } else if let failureKey = state.failureKey {
                    Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240 * metrics.scale), spacing: 18 * metrics.scale)],
                    spacing: 18 * metrics.scale
                ) {
                    ForEach(state.samples) { sample in
                        VStack(alignment: .leading, spacing: 10 * metrics.scale) {
                            Text(LocalizedStringKey(sample.nameKey)).foregroundStyle(.secondary)
                            Text(sample.value, format: .number.precision(.fractionLength(0...2)))
                                .font(.system(size: 36 * metrics.scale, weight: .bold, design: .rounded))
                            Text(sample.unit).foregroundStyle(.secondary)
                        }
                        .padding(20 * metrics.scale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18 * metrics.scale))
                    }
                }

                Button(state.samples.isEmpty ? "telemetry.read" : "telemetry.refresh") {
                    if let endpoint { send(.readRequested(endpoint)) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(endpoint == nil || state.phase == .reading)
            }
            .padding(32 * metrics.scale)
            .frame(maxWidth: 1_180 * metrics.scale)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("macos-live-telemetry")
    }
}
#endif
