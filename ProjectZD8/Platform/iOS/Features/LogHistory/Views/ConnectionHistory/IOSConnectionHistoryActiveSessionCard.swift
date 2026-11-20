#if os(iOS)
import SwiftUI

/// 1件の進行中セッションを記録状態と自動更新の経過時間で示すライブカードです。
struct IOSConnectionHistoryActiveSessionCard: View {
    /// 表示する未終了セッションです。
    let session: ConnectionSession

    /// 車両名称と短縮IDを整形します。
    private let textFormatter = ConnectionHistorySessionTextFormatter()

    /// 記録状態、車両、開始時刻、経過時間を描画します。
    ///
    /// 責務: 1件の未終了セッションを接続中のライブカードへ配置します。
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(.green)
                    .frame(width: 46, height: 46).background(.green.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(textFormatter.vehicleName(session)).font(.system(.headline, design: .rounded, weight: .bold))
                    Text("history.active.recording").font(.caption.weight(.bold)).foregroundStyle(.green)
                }
                Spacer()
                Text(session.startedAt, style: .timer)
                    .font(.system(.title3, design: .monospaced, weight: .bold)).foregroundStyle(.green)
                    .accessibilityLabel(Text("history.active.elapsed"))
            }
            HStack {
                IOSConnectionHistoryLabeledDate(titleKey: "history.started", date: session.startedAt)
                Spacer()
                Text(textFormatter.shortID(session.id)).font(.caption.monospaced().weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [.green.opacity(0.12), Color.primary.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.green.opacity(0.28)) }
        .shadow(color: .green.opacity(0.10), radius: 18, y: 8)
    }
}
#endif
