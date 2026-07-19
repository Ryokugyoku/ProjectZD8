import Foundation

/// 接続履歴の読込範囲、絞り込み、更新をLogHistoryへ通知します。
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
}
