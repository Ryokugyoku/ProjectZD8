import Foundation

/// 交通規制の照合の表示の段階です。
nonisolated enum SessionRoadRegulationReviewStatus: Equatable, Sendable {
    /// セッションを表示していません。
    case idle
    /// 走行ルートの読み込みを待っています。
    case waitingForRoute
    /// 走行ルートが無いため照合できません。
    case routeUnavailable
    /// 車速の記録の読み込みを待っています。
    case waitingForRawLog
    /// 照合しています。
    case evaluating
    /// 照合の結果を表示できます。
    case loaded
    /// 位置の記録が無いため照合できません。
    case noTrack
    /// 交通規制データを取得していないため照合できません。
    case noRegulationData
    /// 照合に失敗しました。
    case failed
}
