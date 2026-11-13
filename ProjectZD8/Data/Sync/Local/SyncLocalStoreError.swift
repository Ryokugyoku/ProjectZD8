/// 同期がローカルデータベースを読み書きする時の失敗です。
nonisolated enum SyncLocalStoreError: Error, Equatable, Sendable {
    /// 対象の行が存在しない。
    case rowNotFound
    /// 行またはレコードの値がスキーマの規則に合わない。値の列名を持ちます。
    case invalidValue(String)
}
