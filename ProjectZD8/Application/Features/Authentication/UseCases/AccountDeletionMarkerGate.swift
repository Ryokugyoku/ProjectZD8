/// アップロード・保存の直前に削除済みの印を確認し、印があれば他端末失効と同じログアウトへ進めます。
@MainActor
final class AccountDeletionMarkerGate {
    /// 削除済みの印を確認する境界です。
    private let marker: any AccountDeletionMarkerPort

    /// 印を検出した時に呼ぶ処理です。App の配線で、他端末失効と同じ端末内ログアウトへ結び付けます。
    var onAccountDeleted: (@MainActor (String) -> Void)?

    /// 印の確認境界を注入します。
    ///
    /// 責務: 削除済みの印の確認を各同期・保存経路から共有できる1つの関門に束ねます。
    /// - Parameter marker: 削除済みの印を確認する境界。
    init(marker: any AccountDeletionMarkerPort) {
        self.marker = marker
    }

    /// 指定アカウントが削除済みでないことを確認します。
    ///
    /// 責務: 印があれば端末内ログアウトを起動してエラーで止め、印の有無を確認できなければエラーをそのまま伝えて今回の処理を見送らせます。
    /// - Parameter accountIdentifier: アップロード・保存しようとしているAppleアカウント識別子。
    /// - Throws: 印がある場合は `AccountDeletionMarkerError.accountDeleted`。確認自体が失敗した場合はその失敗。
    func ensureAccountNotDeleted(for accountIdentifier: String) async throws {
        guard try await marker.isAccountDeleted(accountIdentifier) else { return }
        onAccountDeleted?(accountIdentifier)
        throw AccountDeletionMarkerError.accountDeleted
    }
}
