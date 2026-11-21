import Foundation

/// 1回の走行の交通規制の照合結果です。文言は持たず、判定と数値と出典の材料だけを持ちます。
nonisolated struct SessionRoadRegulationReview: Equatable, Sendable {
    /// 判定の項目です。並びは問いません(State 側で並べます)。
    let entries: [SessionRoadRegulationReviewEntry]
    /// 判定に車速の記録を使えたかどうかです。
    let hasVehicleSpeed: Bool
    /// 判定に使った規制データの版です。
    let datasets: [RoadRegulationDatasetReference]
    /// 使った版の取得日時のうち最も新しいものです。無ければ `nil` です。
    let usedOn: Date?
    /// 規制データの配布ページの URL です。
    let sourceURL: URL
}
