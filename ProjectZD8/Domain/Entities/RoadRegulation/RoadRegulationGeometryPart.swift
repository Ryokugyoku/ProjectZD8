import Foundation

/// 規制の形状を構成する1区間(役割と点の列)です。
nonisolated struct RoadRegulationGeometryPart: Equatable, Sendable {
    /// 区間の役割。
    let role: RoadRegulationGeometryRole
    /// 区間の点の列(線は順序どおり、面は閉じた輪)。
    let coordinates: [GeoCoordinate]
}
