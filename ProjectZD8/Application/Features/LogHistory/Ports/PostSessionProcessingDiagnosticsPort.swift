/// 記録セッション終了後の後処理の予約と実行の経過を、診断記録へ残すための狭い境界です。
///
/// 受け取る値は列挙値とエラーの `domain` / `code` だけです。アカウント識別子・VIN・セッションID・Rawの中身は渡しません。
@MainActor
protocol PostSessionProcessingDiagnosticsPort: AnyObject {
    /// 後処理の実行を予約したことを記録します。
    ///
    /// 責務: 1件の予約成功を診断記録へ渡します。
    func scheduled()

    /// 後処理の実行の予約に失敗したことを記録します。
    ///
    /// 責務: 1件の予約失敗のエラー分類を診断記録へ渡します。
    /// - Parameters:
    ///   - errorDomain: 失敗したエラーの `domain`。
    ///   - errorCode: 失敗したエラーの `code`。
    func scheduleFailed(errorDomain: String, errorCode: Int)

    /// 後処理の実行を始めたことを記録します。
    ///
    /// 責務: 1件の実行開始を診断記録へ渡します。
    func started()

    /// 記録中のため残りの処理を次回へ持ち越したことを記録します。
    ///
    /// 責務: 1件の記録中による持ち越しを診断記録へ渡します。
    func deferredForActiveRecording()

    /// アカウントを解決できないため処理を次回へ持ち越したことを記録します。
    ///
    /// 責務: 1件のアカウント未解決による持ち越しを診断記録へ渡します。
    func deferredForUnavailableAccount()

    /// 自動アップロードの設定がオフのため、アップロード系のステップを省いたことを記録します。
    ///
    /// 責務: 1件の設定によるステップの省略を、省いたステップとともに診断記録へ渡します。
    /// - Parameter step: 省いたステップ。
    func stepSkippedForAutomaticUploadOff(_ step: PostSessionProcessingStep)

    /// ステップが成功したことを記録します。
    ///
    /// 責務: 1件のステップ成功を診断記録へ渡します。
    /// - Parameter step: 成功したステップ。
    func stepSucceeded(_ step: PostSessionProcessingStep)

    /// ステップが失敗したことを記録します。
    ///
    /// 責務: 1件のステップ失敗とそのエラー分類を診断記録へ渡します。
    /// - Parameters:
    ///   - step: 失敗したステップ。
    ///   - errorDomain: 失敗したエラーの `domain`。
    ///   - errorCode: 失敗したエラーの `code`。
    func stepFailed(_ step: PostSessionProcessingStep, errorDomain: String, errorCode: Int)

    /// 実行期限切れ(キャンセル)のため残りの処理を中断したことを記録します。
    ///
    /// 責務: 1件の期限切れによる中断を診断記録へ渡します。
    func interruptedByExpiration()

    /// 後処理の実行を終えたことを記録します。
    ///
    /// 責務: 1件の実行結果を診断記録へ渡します。
    /// - Parameter outcome: 実行結果。`completed` 以外は未完了として扱います。
    func finished(_ outcome: PostSessionProcessingOutcome)
}
