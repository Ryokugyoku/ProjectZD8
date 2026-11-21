import Foundation

/// 走行ルートと解析の読み込みの段階から決まる、交通規制の照合を始められるかどうかです。
nonisolated enum SessionRoadRegulationReviewReadiness: Equatable, Sendable {
    /// 走行ルートの読み込みを待っています(ルートが idle / waitingForAccount / loading)。
    case waitingForRoute
    /// 走行ルートがありません(ルートが unavailable / failed)。
    case routeUnavailable
    /// 車速の記録の読み込みを待っています(ルートは ready、解析が idle / downloading / loading)。
    case waitingForRawLog
    /// 照合を始められます。車速の記録の在りかを添えます。
    case ready(SessionRoadRegulationRawLogAvailability)
}
