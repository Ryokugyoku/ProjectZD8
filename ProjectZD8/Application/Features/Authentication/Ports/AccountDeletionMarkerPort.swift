/// アカウント削除済みの印をクラウドへ保存・確認・解除する境界です。
///
/// 印は削除時刻だけを持ち、個人情報を含みません。オフラインだった他端末が削除済みデータを再アップロードするのを防ぎます。
@MainActor
protocol AccountDeletionMarkerPort: AnyObject {
    /// 指定アカウントの削除済みの印があるかを返します。
    ///
    /// 責務: 1件のアカウントについてクラウド上の印の有無を照会します。印が無い場合は `false` を返します。
    /// - Parameter accountIdentifier: 照会対象のAppleアカウント識別子。
    /// - Returns: 印が存在する場合は `true`。
    /// - Throws: 通信エラーなどで有無を確認できない場合のエラー。確認できない場合を「印なし」にしてはいけません。
    func isAccountDeleted(_ accountIdentifier: String) async throws -> Bool

    /// 指定アカウントの削除済みの印を保存します。
    ///
    /// 責務: 1件のアカウントのクラウド削除が完了したことを、削除時刻だけを持つ印として残します。
    /// - Parameter accountIdentifier: 削除したAppleアカウント識別子。
    /// - Throws: 印を保存できない場合のエラー。
    func markDeleted(_ accountIdentifier: String) async throws

    /// 指定アカウントの削除済みの印を消します。
    ///
    /// 責務: 同じAppleアカウントで新しくサインインし直す前に、過去の削除の印を無効にします。印が無ければ成功とします。
    /// - Parameter accountIdentifier: 利用を再開するAppleアカウント識別子。
    /// - Throws: 印を消せない場合のエラー。
    func clearMarker(_ accountIdentifier: String) async throws
}
