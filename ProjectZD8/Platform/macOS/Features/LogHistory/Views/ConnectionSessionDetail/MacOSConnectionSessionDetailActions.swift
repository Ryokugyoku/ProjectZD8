#if os(macOS)
import SwiftUI

/// macOS のセッション詳細で、一覧へ戻る操作と全端末からの削除操作を表示します。
struct MacOSConnectionSessionDetailActions: View {
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 削除操作を表示するかを示します。終了済みのセッションだけ `true` です。
    let canDelete: Bool
    /// 表示対象を全端末から削除している途中かを示します。
    let isDeleting: Bool
    /// 車両セッション一覧へ戻る操作です。
    let onBack: () -> Void
    /// 削除の要求を送出します。
    let onDelete: () -> Void

    /// 左に戻るボタン、右に削除ボタンを描画します。
    ///
    /// 責務: 戻る操作と、削除できる時だけ削除中は進捗表示に切り替わる削除ボタンを並べます。
    var body: some View {
        HStack(spacing: 12 * scale) {
            Button(action: onBack) {
                Label("history.detail.back", systemImage: "chevron.left")
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .frame(minHeight: 32 * scale)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("macos-history-session-back")
            Spacer()
            if canDelete {
                deleteButton
            }
        }
    }

    /// 削除中は進捗表示に切り替わる削除ボタンです。
    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            if isDeleting {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 128 * scale, minHeight: 32 * scale)
            } else {
                Label("history.delete.button", systemImage: "trash")
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .frame(minHeight: 32 * scale)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.red.opacity(0.88))
        .disabled(isDeleting)
        .accessibilityIdentifier("macos-history-delete-session")
    }
}
#endif
