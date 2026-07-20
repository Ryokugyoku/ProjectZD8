#if os(macOS)
import SwiftUI

/// macOSでアカウント削除の警告、削除事項、実行状態を表示します。
struct MacOSAccountDeletionFlowView: View {
    /// Applicationが提供するアカウント削除の現在段階です。
    let phase: AccountDeletionPhase

    /// Applicationが保持する直近の削除失敗です。
    let failure: AccountDeletionFailure?

    /// アカウント削除画面の型付き操作をApplicationへ通知します。
    let send: (AuthenticationAction) -> Void

    /// macOSウインドウ内で警告と削除事項を順番に提示します。
    ///
    /// 責務: Applicationの削除段階をmacOSの2段階確認画面へ表示します。
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert(
                "account.delete.warning.title",
                isPresented: warningBinding
            ) {
                Button("account.delete.cancel", role: .cancel) {
                    send(.accountDeletionCancelled)
                }
                Button("account.delete.next") {
                    send(.accountDeletionWarningConfirmed)
                }
            } message: {
                Text("account.delete.warning.message")
            }
            .sheet(isPresented: reviewBinding) {
                reviewSheet
            }
    }

    /// 最初の警告段階だけをAlert表示へ結び付けます。
    private var warningBinding: Binding<Bool> {
        Binding(
            get: { phase == .warning },
            set: { _ in }
        )
    }

    /// 削除事項、実行中、失敗の各段階を同じSheet表示へ結び付けます。
    private var reviewBinding: Binding<Bool> {
        Binding(
            get: { phase == .reviewing || phase == .deleting || phase == .failed },
            set: { isPresented in
                if !isPresented, phase != .deleting {
                    send(.accountDeletionCancelled)
                }
            }
        )
    }

    /// 削除対象事項と最終削除操作をMac向けパネルとして表示します。
    private var reviewSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 15) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 48, height: 48)
                    .background(.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("account.delete.review.title")
                        .font(.title2.bold())
                        .accessibilityIdentifier("macos-account-delete-review")
                    Text("account.delete.review.message")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(24)

            Divider()

            VStack(spacing: 12) {
                deletionItem(symbol: "car.fill", key: "account.delete.item.driving_data")
                deletionItem(symbol: "car.2.fill", key: "account.delete.item.vehicles")
                deletionItem(symbol: "icloud.slash", key: "account.delete.item.shared_settings")
                deletionItem(symbol: "cable.connector.slash", key: "account.delete.item.adapter")
                deletionItem(symbol: "key.slash", key: "account.delete.item.credential")

                if failure != nil {
                    Label("account.delete.error", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)

            Divider()

            HStack(spacing: 12) {
                Button("account.delete.cancel") {
                    send(.accountDeletionCancelled)
                }
                .keyboardShortcut(.cancelAction)
                .disabled(phase == .deleting)
                Spacer()
                Button(role: .destructive) {
                    send(.accountDeletionConfirmed)
                } label: {
                    HStack(spacing: 8) {
                        if phase == .deleting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(phase == .failed ? "account.delete.retry" : "account.delete.confirm")
                    }
                    .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(phase == .deleting)
                .accessibilityIdentifier("macos-account-delete-confirm")
            }
            .padding(20)
        }
        .frame(minWidth: 520, idealWidth: 600)
        .interactiveDismissDisabled(phase == .deleting)
    }

    /// 1件の削除対象をアイコン付きの説明行として描画します。
    ///
    /// 責務: 1件の削除事項をmacOS確認画面で読み取れる行へ変換します。
    /// - Parameters:
    ///   - symbol: 削除対象を補助するSF Symbol名。
    ///   - key: 削除対象を説明するローカライズキー。
    /// - Returns: 削除対象1件のmacOS表示。
    private func deletionItem(
        symbol: String,
        key: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 34, height: 34)
                .background(.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            Text(key)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }
}
#endif
