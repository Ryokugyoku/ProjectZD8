import Foundation

/// 保存前の交通規制1件です。行 ID と所属する版を持たないほかは `RoadRegulation` と同じ項目です。
nonisolated struct RoadRegulationDraft: Equatable, Sendable {
    /// JARTIC のユニークキー。
    let uniqueKey: String
    /// 規制の種別。
    let kind: RoadRegulationKind
    /// 最高速度(km/h)。区間(112)と区域(114)だけが持ちます。
    let speedLimitKph: Int?
    /// 片側・両側の別。不明なら `nil`。
    let side: RoadRegulationSideCode?
    /// 一方通行の座標の並び方。一方通行だけが持ちます。
    let oneWayOrder: RoadRegulationOneWayOrder?
    /// 外周道路を含むか。不明なら `nil`。
    let perimeterRoadIncluded: Bool?
    /// 対象・除外の条件(生のコード)。
    let conditions: RoadRegulationConditions
    /// 形状。
    let geometry: RoadRegulationGeometry
}
