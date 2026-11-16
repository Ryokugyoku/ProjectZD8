/// 認証入口からApplicationへ通知できるユーザー操作を表します。
enum AuthenticationAction: Equatable {
    /// 認証入口が表示され、保存済みセッションの確認を要求しました。
    case appeared

    /// アプリが前面へ戻りました。サインイン確認が照会の失敗のまま解決していなければ、直ちに再確認し、時間経過の再確認の回数を取り直します。
    case foregroundEntered

    /// ユーザーがログイン手続きの開始を要求しました。
    case loginTapped

    /// ユーザーが免責事項を閉じました。
    case disclaimerDismissed

    /// ユーザーが免責事項への同意とApple認証の開始を要求しました。
    case disclaimerAccepted

    /// ユーザーが失敗後の再試行を要求しました。
    case retryTapped

    /// ユーザーが設定画面からアカウント削除確認を開始しました。
    case accountDeletionRequested

    /// ユーザーが最初の警告を確認して削除事項の表示を要求しました。
    case accountDeletionWarningConfirmed

    /// ユーザーがアカウント削除確認を取り消しました。
    case accountDeletionCancelled

    /// ユーザーが削除事項を確認して最終削除を要求しました。
    case accountDeletionConfirmed
}
