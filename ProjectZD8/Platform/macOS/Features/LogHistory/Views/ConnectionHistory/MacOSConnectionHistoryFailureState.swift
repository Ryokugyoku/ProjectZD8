#if os(macOS)
import SwiftUI

/// 履歴保存先を利用できない状態と再試行操作を示す失敗状態です。
struct MacOSConnectionHistoryFailureState: View {
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 再試行ボタンの押下時に呼ぶ操作です。
    let retry: () -> Void

    /// 警告アイコン、説明、再試行ボタンを描画します。
    ///
    /// 責務: 保存先の利用不能を警告と再試行操作へ配置します。
    var body: some View {
        VStack(spacing: 14 * scale) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 34 * scale)).foregroundStyle(.orange)
            Text("history.error.storage").font(.system(size: 15 * scale, weight: .semibold))
            Button("history.error.retry", action: retry).buttonStyle(.borderedProminent)
        }.padding(34 * scale).frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 24 * scale, style: .continuous))
    }
}
#endif
