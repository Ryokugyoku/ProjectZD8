import AppIntents
import SwiftUI

/// 受信件数と[切断]ボタンを並べた最下段です。
struct RecordingSessionLiveActivityFooterView: View {
    /// このセッションで受信した応答の件数です。
    let receivedResponseCount: Int

    /// 受信件数を左に、[切断]ボタンを右に描きます。[切断]は `StopRecordingSessionIntent` をアプリのプロセスで実行します。
    var body: some View {
        HStack {
            Text("live_activity.received_count \(receivedResponseCount)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(intent: StopRecordingSessionIntent()) {
                Label(
                    LocalizedStringKey(RecordingSessionActivityAttributes.stopButtonKey),
                    systemImage: RecordingSessionLiveActivityStatusSymbol.stopActionName
                )
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(RecordingSessionLiveActivityPalette.accent)
        }
    }
}
