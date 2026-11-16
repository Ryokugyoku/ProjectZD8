/// 削除の失敗の原因に対応する案内文のローカライズキーを選びます。
enum AccountDeletionFailureMessage {
    /// 原因に対応するローカライズキーを返します。
    ///
    /// 責務: 1件の失敗の原因を、View が `LocalizedStringKey` へ変換できる案内文キーへ対応付けます。
    /// - Parameter failure: 表示する失敗の原因。
    /// - Returns: `Localizable.xcstrings` のキー。
    static func key(for failure: AccountDeletionFailure) -> String {
        switch failure {
        case .iCloudUnavailable: "account.delete.error.icloud"
        case .networkUnavailable: "account.delete.error.network"
        case .serviceBusy: "account.delete.error.busy"
        case .acquisitionTimedOut: "account.delete.error.acquisition_timeout"
        case .deletionFailed: "account.delete.error"
        }
    }
}
