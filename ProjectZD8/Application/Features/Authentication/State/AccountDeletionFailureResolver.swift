/// アカウント削除で投げられたエラーを、表示する失敗の原因へ決定します。
struct AccountDeletionFailureResolver {
    /// 基盤固有のエラーを分類する境界です。未設定なら分類せず `.deletionFailed` にします。
    private let classifier: (any AccountDeletionFailureClassifying)?

    /// 分類境界を注入します。
    ///
    /// 責務: Application自身が知るエラーと、基盤が分類するエラーの判定順序を固定します。
    /// - Parameter classifier: 基盤固有のエラーの分類境界。省略時は分類しません。
    init(classifier: (any AccountDeletionFailureClassifying)? = nil) {
        self.classifier = classifier
    }

    /// エラーから失敗の原因を決めます。
    ///
    /// 責務: 記録の終了待ちのタイムアウトを先に判定し、それ以外は基盤の分類へ委ね、分類できなければ `.deletionFailed` にします。
    /// - Parameter error: アカウント削除中に投げられたエラー。
    /// - Returns: 表示に使う失敗の原因。
    func failure(for error: Error) -> AccountDeletionFailure {
        if let drainError = error as? AccountDeletionAcquisitionDrainError, drainError == .timedOut {
            return .acquisitionTimedOut
        }
        return classifier?.failure(for: error) ?? .deletionFailed
    }
}
