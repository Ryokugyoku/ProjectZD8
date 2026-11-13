/// 実車データとデモデータの絞り込みです。
nonisolated enum LogHistoryDataKindFilter: String, CaseIterable, Sendable {
    case all
    case real
    case demo

    /// 画面表示に使用するローカライズキーです。
    var nameKey: String { "history.filter.data_kind.\(rawValue)" }

    /// 責務: セッションが条件に合うかを返します。
    func matches(isDemo: Bool) -> Bool {
        switch self {
        case .all: true
        case .real: !isDemo
        case .demo: isDemo
        }
    }
}
