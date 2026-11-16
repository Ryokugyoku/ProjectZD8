/// アカウント削除の開始時に、進行中の取得(記録)を終わらせて保存完了まで待つ境界です。
@MainActor
protocol AccountDeletionAcquisitionDrainPort: AnyObject {
    /// 進行中の取得を終了させ、終了処理(取得記録とセッションの保存)が終わるまで待ちます。
    ///
    /// 責務: クラウド削除より前に、記録中の取得が無い状態を作ります。待ちには上限があり、超えたら失敗として投げます。
    /// - Throws: 上限までに取得の終了を確認できない場合は `AccountDeletionAcquisitionDrainError.timedOut`。
    func endAcquisitionAndWaitUntilSaved() async throws
}
