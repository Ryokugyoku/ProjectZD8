#if os(iOS)
import SwiftUI

/// iOSで主要PID読取の提供状態と数値を描画します。
struct IOSLiveTelemetryView: View {
    /// Applicationが公開するPID読取状態です。
    let state: LiveTelemetryState
    /// PID読取操作の通知先です。
    let send: (LiveTelemetryAction) -> Void

    /// モバイル専用の主要PID読取表示を提供します。
    ///
    /// 責務: LiveTelemetry状態をiOS専用の読取操作と数値カードへ変換します。
    var body: some View {
        NavigationStack {
            List {
                if state.phase == .reading { ProgressView("telemetry.status.reading") }
                if state.phase == .stopping { ProgressView("telemetry.status.stopping") }
                if let failureKey = state.failureKey {
                    Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                ForEach(state.samples) { sample in
                    LabeledContent(LocalizedStringKey(sample.nameKey)) {
                        Text("\(sample.value, format: .number.precision(.fractionLength(0...2))) \(sample.unit)")
                    }
                }
                if state.phase == .loaded {
                    Label("telemetry.status.streaming", systemImage: "waveform.path.ecg")
                        .foregroundStyle(.green)
                } else if state.phase == .failed {
                    Button("telemetry.retry") { send(.retryRequested) }
                } else if state.phase == .idle {
                    Text("telemetry.status.waiting_for_connection")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("telemetry.title")
        }
        .accessibilityIdentifier("ios-live-telemetry")
    }
}
#endif
