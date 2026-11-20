/// 位置を一時的に取得できない理由です。
nonisolated enum LocationUnavailableReason: String, Equatable, Sendable {
    /// 一時的に取得できません(例: 測位の見失い)。回復する可能性があります。
    case temporarilyUnavailable
    /// 取得に失敗しました。
    case failed
}
