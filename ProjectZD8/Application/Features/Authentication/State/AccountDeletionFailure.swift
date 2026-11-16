/// アカウント削除画面が区別して表示する失敗です。
enum AccountDeletionFailure: Equatable {
    /// iCloudにサインインしていない、または利用が制限されているため、クラウドのデータを削除できませんでした。
    case iCloudUnavailable

    /// 通信できないため、クラウドのデータを削除できませんでした。
    case networkUnavailable

    /// サービスが混み合っているため、クラウドのデータを削除できませんでした。時間をおいて再試行できます。
    case serviceBusy

    /// 進行中の記録の終了を、上限までに確認できませんでした。
    case acquisitionTimedOut

    /// 上のいずれにも分類できない原因で、CloudKit、ローカルデータ、または保存済みログイン識別子を完全に削除できませんでした。
    case deletionFailed
}
