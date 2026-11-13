/// 永続化層が返す失敗です。
nonisolated enum StoreError: Error, Equatable, Sendable {
    /// 対象が存在しない。
    case notFound
    /// 状態遷移や整合性の規則に反する操作だった。
    case invalidState
    /// データベースやファイルの入出力に失敗した。
    case ioFailure
}
