import Foundation

/// 1回の走行を交通規制データと照合した結果です。照合できない理由も値で表します。
nonisolated enum SessionRoadRegulationReviewResult: Equatable, Sendable {
    /// 照合できました。
    case reviewed(SessionRoadRegulationReview)
    /// 位置の記録が無いため照合できません。
    case noTrack
    /// 交通規制データを取得していないため照合できません。
    case noRegulationData
}
