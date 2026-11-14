/// 接続履歴画面が提示する alert の種類です。
///
/// View は `allCases` の順に alert を接続し、各種類の内容を `ConnectionHistoryAlertFactory` から得ます。
enum ConnectionHistoryAlertKind: CaseIterable, Equatable, Sendable {
    /// ローカルRawログ容量解放の確認です。
    case rawRemovalConfirmation
    /// 全端末セッション削除の確認です。
    case sessionDeletionConfirmation
    /// 全端末セッション削除の失敗通知です。
    case sessionDeletionFailure
    /// ユーザー操作による停止かの確認です。
    case stopReviewConfirmation
    /// 停止確認保存の失敗通知です。
    case stopReviewFailure
    /// iCloud個別アップロードの失敗通知です。
    case uploadFailure
}
