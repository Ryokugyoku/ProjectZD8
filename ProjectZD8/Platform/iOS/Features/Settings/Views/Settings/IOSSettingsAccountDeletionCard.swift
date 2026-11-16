#if os(iOS)
import SwiftUI

/// iOS設定画面で通常設定から視覚的に分離したアカウント削除カードを描画します。
struct IOSSettingsAccountDeletionCard: View {
    /// アカウント削除の開始が求められたことを通知するクロージャです。
    let requestDeletion: () -> Void

    /// 警告色の説明と削除開始ボタンを持つカードを提供します。
    ///
    /// 責務: アカウント削除の入口を、取り消せない操作と分かる見た目で描画します。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSSettingsMetrics.accountDeletionSpacing) {
            Label("account.delete.card.title", systemImage: "exclamationmark.shield.fill")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.red)
            Text("account.delete.card.description")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("account.delete.start", role: .destructive, action: requestDeletion)
                .buttonStyle(.bordered)
                .frame(minHeight: IOSSettingsMetrics.accountDeletionButtonMinHeight)
                .accessibilityIdentifier("ios-account-delete-start")
        }
        .padding(IOSSettingsMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .red.opacity(IOSSettingsMetrics.accountDeletionFillOpacity),
            in: RoundedRectangle(cornerRadius: IOSSettingsMetrics.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: IOSSettingsMetrics.cardCornerRadius, style: .continuous)
                .stroke(.red.opacity(IOSSettingsMetrics.accountDeletionStrokeOpacity), lineWidth: 1)
        }
    }
}
#endif
