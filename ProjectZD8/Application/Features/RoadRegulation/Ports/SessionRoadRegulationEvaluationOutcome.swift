import Foundation

/// 走行の規制の判定を求めた結果です。
nonisolated enum SessionRoadRegulationEvaluationOutcome: Equatable, Sendable {
    /// 判定した。
    case evaluated(SessionRoadRegulationReport)
    /// 位置の記録が無い。
    case noTrack
    /// 取得済みの規制データが無い。
    case noRegulationData
}
