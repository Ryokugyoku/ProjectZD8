#if os(iOS)
import SwiftUI

/// iPhone のセッション詳細で、iCloud を含む完全削除の操作を表示します。
struct IOSConnectionSessionDetailActions: View {
    /// 削除操作を表示するかを示します。終了済みのセッションだけ `true` です。
    let canDelete: Bool
    /// 表示対象を iCloud を含めて削除している途中かを示します。
    let isDeleting: Bool
    /// 削除の要求を送出します。
    let onDelete: () -> Void

    /// 右寄せの削除ボタンを描画します。
    ///
    /// 責務: 削除できる時だけ、削除中は進捗表示に切り替わる削除ボタンを描画します。
    var body: some View {
        HStack {
            Spacer()
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    if isDeleting {
                        ProgressView().frame(minWidth: 120)
                    } else {
                        Label("history.delete.button", systemImage: "trash")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.88))
                .disabled(isDeleting)
                .accessibilityIdentifier("ios-history-delete-session")
            }
        }
    }
}
#endif
