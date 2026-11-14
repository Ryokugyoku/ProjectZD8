#if os(macOS)
import SwiftUI

/// 1件の進行中セッションを記録状態と自動更新経過時間で示すライブカードです。
struct MacOSConnectionHistoryActiveSessionCard: View {
    /// 表示する未終了セッションです。
    let session: ConnectionSession
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 車両名称を表示用文字列へ整形します。
    private let textFormatter = ConnectionHistorySessionTextFormatter()

    /// 記録状態、車両、経過時間、開始時刻を描画します。
    ///
    /// 責務: 1件の未終了セッションを接続中のライブカードへ配置します。
    var body: some View {
        HStack(spacing: 18 * scale) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 24 * scale, weight: .semibold)).foregroundStyle(.green)
                .frame(width: 58 * scale, height: 58 * scale)
                .background(.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(textFormatter.vehicleName(session)).font(.system(size: 17 * scale, weight: .bold, design: .rounded))
                Text("history.active.recording").font(.system(size: 10.5 * scale, weight: .bold)).foregroundStyle(.green)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4 * scale) {
                Text("history.active.elapsed").font(.system(size: 9 * scale, weight: .semibold)).foregroundStyle(.tertiary)
                Text(session.startedAt, style: .timer)
                    .font(.system(size: 25 * scale, weight: .bold, design: .monospaced)).foregroundStyle(.green)
            }
            Divider().frame(height: 42 * scale)
            VStack(alignment: .trailing, spacing: 4 * scale) {
                Text("history.started").font(.system(size: 9 * scale, weight: .semibold)).foregroundStyle(.tertiary)
                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.system(size: 11 * scale, weight: .semibold, design: .monospaced))
            }
        }
        .padding(20 * scale)
        .background(
            LinearGradient(
                colors: [.green.opacity(0.115), Color.primary.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
        )
        .overlay { RoundedRectangle(cornerRadius: 22 * scale, style: .continuous).stroke(.green.opacity(0.28)) }
        .shadow(color: .green.opacity(0.09), radius: 16 * scale, y: 7 * scale)
    }
}
#endif
