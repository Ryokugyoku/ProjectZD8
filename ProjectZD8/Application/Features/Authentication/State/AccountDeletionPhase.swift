/// アカウント削除確認と実行の進行段階です。
enum AccountDeletionPhase: Equatable {
    /// 削除確認を表示していない通常状態です。
    case idle

    /// 削除が取り消せないことを最初に警告している状態です。
    case warning

    /// 削除対象事項と最終削除操作を表示している状態です。
    case reviewing

    /// アカウントデータを削除している状態です。
    case deleting

    /// 削除を完了できず同じ画面から再試行できる状態です。
    case failed
}
