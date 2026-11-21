import Foundation

/// 保存済みの交通規制1件です。
nonisolated struct RoadRegulation: Equatable, Sendable {
    /// 規制の行 ID。
    let id: RoadRegulationID
    /// 所属する版。
    let datasetID: RoadRegulationDatasetID
    /// JARTIC のユニークキー(版の中で一意)。
    let uniqueKey: String
    /// 規制の種別。
    let kind: RoadRegulationKind
    /// 最高速度(km/h)。区間(112)と区域(114)だけが持ち、ほかは `nil`。
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
