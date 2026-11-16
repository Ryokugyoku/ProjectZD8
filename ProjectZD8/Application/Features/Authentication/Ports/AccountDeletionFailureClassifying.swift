/// 基盤(CloudKitなど)のエラーを、削除画面に表示する失敗の原因へ分類する境界です。
protocol AccountDeletionFailureClassifying {
    /// 1件のエラーを失敗の原因へ分類します。
    ///
    /// 責務: 基盤固有のエラーを `AccountDeletionFailure` へ変換します。分類できなければ `.deletionFailed` を返します。
    /// - Parameter error: アカウント削除中に投げられたエラー。
    /// - Returns: 表示に使う失敗の原因。
    func failure(for error: Error) -> AccountDeletionFailure
}
