import GRDB

/// セグメント・欠損・CANフレーム保存の失敗を接続セッションRepositoryの失敗理由へ変換します。
nonisolated struct GRDBConnectionSessionSegmentationErrorTranslator {
    /// 任意の失敗を `ConnectionSessionRepositoryError` へ変換します。
    ///
    /// 責務: 既に分類済みの失敗はそのまま、SQLite制約違反は整合性エラー、それ以外は保存先利用不可へ分類します。
    /// - Parameter error: Record変換またはGRDBが送出した失敗。
    /// - Returns: 呼び出し側へ返す接続セッションRepositoryの失敗理由。
    func repositoryError(for error: any Error) -> ConnectionSessionRepositoryError {
        if let error = error as? ConnectionSessionRepositoryError {
            return error
        }
        if let error = error as? DatabaseError, error.resultCode == .SQLITE_CONSTRAINT {
            return .integrityConflict
        }
        return .unavailable
    }
}
