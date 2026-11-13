/// 履歴の並び順です。
nonisolated enum LogHistorySortOrder: String, CaseIterable, Sendable {
    /// 開始日時が新しい順です。
    case newest
    /// 開始日時が古い順です。
    case oldest
    /// 記録時間が長い順です。
    case longestDuration
    /// 記録時間が短い順です。
    case shortestDuration

    /// 画面表示に使用するローカライズキーです。
    var nameKey: String { "history.sort.\(rawValue)" }

    /// 責務: 2件の行を並び順で比較し、左を先に置くかを返します。
    func areInIncreasingOrder(_ lhs: LogHistorySessionRow, _ rhs: LogHistorySessionRow) -> Bool {
        switch self {
        case .newest: lhs.startedAt > rhs.startedAt
        case .oldest: lhs.startedAt < rhs.startedAt
        case .longestDuration: (lhs.duration ?? 0) > (rhs.duration ?? 0)
        case .shortestDuration: (lhs.duration ?? 0) < (rhs.duration ?? 0)
        }
    }
}
