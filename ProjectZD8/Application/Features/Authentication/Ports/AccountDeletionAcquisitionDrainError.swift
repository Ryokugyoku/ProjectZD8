/// 削除前の取得終了待ちが完了しなかった理由です。
enum AccountDeletionAcquisitionDrainError: Error, Equatable {
    /// 上限までに進行中の取得の終了を確認できませんでした。
    case timedOut
}
