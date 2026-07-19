/// 接続履歴の読込範囲と更新をLogHistoryへ通知します。
enum ConnectionHistoryAction: Equatable {
    /// 現在の認証アカウントへ読込範囲を切り替えます。
    case accountIdentifierChanged(String?)
    /// 現在アカウントの履歴再読込を要求します。
    case refreshRequested
}
