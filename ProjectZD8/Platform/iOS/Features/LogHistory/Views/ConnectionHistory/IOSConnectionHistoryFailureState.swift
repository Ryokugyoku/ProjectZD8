#if os(iOS)
import SwiftUI

/// 履歴の保存先を利用できない状態と再試行操作を示す表示です。
struct IOSConnectionHistoryFailureState: View {
    /// 再試行が選ばれたことを通知します。
    let retry: () -> Void

    /// 失敗のアイコン、説明、再試行ボタンを描画します。
    ///
    /// 責務: 保存先を利用できないことを再試行操作付きの表示へ配置します。
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 32)).foregroundStyle(.orange)
            Text("history.error.storage").font(.headline).multilineTextAlignment(.center)
            Button("history.error.retry") { retry() }.buttonStyle(.borderedProminent)
        }
        .padding(28).frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
#endif
