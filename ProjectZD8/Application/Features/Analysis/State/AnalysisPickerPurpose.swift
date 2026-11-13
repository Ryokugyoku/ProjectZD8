/// セッション選択UIを開く目的です。
nonisolated enum AnalysisPickerPurpose: Equatable, Sendable {
    /// 表示中のセッションを選び直す。
    case replacePrimary
    /// 比較用に別のセッションを追加する。
    case addComparison
}
