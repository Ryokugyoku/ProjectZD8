#if os(iOS)
import SwiftUI

/// iOSで主要PID読取の提供状態と数値を描画します。
struct IOSLiveTelemetryView: View {
    /// Applicationが公開するPID読取状態です。
    let state: LiveTelemetryState
    /// 現在設定されているOBD終端です。
    let endpoint: OBDConnectionEndpoint?
    /// PID読取操作の通知先です。
    let send: (LiveTelemetryAction) -> Void

    /// モバイル専用の主要PID読取表示を提供します。
    ///
    /// 責務: LiveTelemetry状態をiOS専用の読取操作と数値カードへ変換します。
    var body: some View {
        NavigationStack {
            List {
                if state.phase == .reading { ProgressView("telemetry.status.reading") }
                if let failureKey = state.failureKey {
                    Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                ForEach(state.samples) { sample in
                    LabeledContent(LocalizedStringKey(sample.nameKey)) {
                        Text(sample.value, format: .number.precision(.fractionLength(0...2))) + Text(" \(sample.unit)")
                    }
                }
                Button(state.samples.isEmpty ? "telemetry.read" : "telemetry.refresh") {
                    if let endpoint { send(.readRequested(endpoint)) }
                }
                .disabled(endpoint == nil || state.phase == .reading)
            }
            .navigationTitle("telemetry.title")
        }
        .accessibilityIdentifier("ios-live-telemetry")
    }
}
#endif
