import Foundation

/// 交通規制データのリポジトリが投げる失敗です。
nonisolated enum RoadRegulationRepositoryError: Error, Equatable, Sendable {
    /// 保存先が使えない、またはその他の保存・読取の失敗。
    case unavailable
    /// 保存値を復元できない、または制約に違反した。
    case integrityConflict
    /// 保存領域が足りない(SQLITE_FULL)。
    case storageFull
    /// 指定した版が無い。
    case notFound
}
