import Foundation

/// 接続履歴の読込範囲、絞り込み、更新、削除をLogHistoryへ通知します。
enum ConnectionHistoryAction: Equatable {
    /// 現在の認証アカウントへ読込範囲を切り替えます。
    case accountIdentifierChanged(String?)
    /// 現在アカウントの履歴再読込を要求します。
    case refreshRequested
    /// セッション一覧へ適用する開始日を変更します。
    case filterStartDateChanged(Date?)
    /// セッション一覧へ適用する終了日を変更します。
    case filterEndDateChanged(Date?)
    /// セッション一覧へ適用する終了理由を変更します。
    case endReasonFilterChanged(ConnectionHistoryEndReasonFilter)
    /// セッション一覧の並び順を変更します。
    case sortOrderChanged(ConnectionHistorySortOrder)
    /// セッション一覧の絞り込み条件を初期化します。
    case filtersReset
    /// 指定セッションをこのiPhoneから取り除く前の確認を要求します。
    case localRawRemovalRequested(ConnectionSessionID)
    /// 表示中の確認内容を承知してローカルRawログ除去を確定します。
    case localRawRemovalConfirmed
    /// ローカルRawログ除去の確認を取り消します。
    case localRawRemovalCancelled
    /// 指定セッションを全端末から物理削除する前の確認を要求します。
    case sessionDeletionRequested(ConnectionSessionID)
    /// 表示中の警告を承知して全端末削除を確定します。
    case sessionDeletionConfirmed
    /// 全端末削除の確認を取り消します。
    case sessionDeletionCancelled
    /// 全端末削除失敗の通知を閉じます。
    case sessionDeletionFailureDismissed
}
