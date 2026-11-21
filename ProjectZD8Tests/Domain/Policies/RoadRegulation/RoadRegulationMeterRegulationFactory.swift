import Foundation
@testable import ProjectZD8

/// 候補・向き・一時停止のテストで、原点(北緯26.2度・東経127.7度。升目の角にあたる)から東へ x m・北へ y m の形状で
/// 規制を組み立てる補助です。座標は `GeoTestCoordinates` で独立に計算します。
enum RoadRegulationMeterRegulationFactory {
    /// メートル単位の点です(x が東、y が北)。
    typealias MeterPoint = (x: Double, y: Double)

    /// 責務: 原点から東へ x m・北へ y m の座標を返します。
    /// - Parameter point: メートル単位の点。
    /// - Returns: 座標。
    static func coordinate(_ point: MeterPoint) -> GeoCoordinate {
        GeoTestCoordinates().point(x: point.x, y: point.y)
    }

    /// 責務: 線の規制(既定は最高速度の区間 40 km/h)を作ります。
    /// - Parameters:
    ///   - id: 規制の行 ID。
    ///   - kind: 種別(線の種別を渡す)。
    ///   - points: 規制場所の点の列(座標の並び順)。
    ///   - speedLimitKph: 最高速度。
    ///   - oneWayOrder: 一方通行の座標の並び方。
    ///   - exclusion: 除外区間の点の列。無ければ `nil`。
    /// - Returns: 規制。
    static func line(
        id: Int64,
        kind: RoadRegulationKind = .speedLimitSection,
        points: [MeterPoint],
        speedLimitKph: Int? = 40,
        oneWayOrder: RoadRegulationOneWayOrder? = nil,
        exclusion: [MeterPoint]? = nil
    ) -> RoadRegulation {
        var parts = [RoadRegulationGeometryPart(role: .main, coordinates: points.map(coordinate))]
        if let exclusion {
            parts.append(RoadRegulationGeometryPart(role: .exclusion, coordinates: exclusion.map(coordinate)))
        }
        return regulation(id: id, kind: kind, speedLimitKph: speedLimitKph, oneWayOrder: oneWayOrder, parts: parts)
    }

    /// 責務: 一方通行(11)の線の規制を作ります。
    /// - Parameters:
    ///   - id: 規制の行 ID。
    ///   - points: 規制場所の点の列。
    ///   - order: 座標の並び方。
    /// - Returns: 規制。
    static func oneWay(id: Int64, points: [MeterPoint], order: RoadRegulationOneWayOrder) -> RoadRegulation {
        line(id: id, kind: .oneWay, points: points, speedLimitKph: nil, oneWayOrder: order)
    }

    /// 責務: 停止点1つと、進入方向の点を1点ずつ別の区間に持つ一時停止(63)を作ります。
    /// - Parameters:
    ///   - id: 規制の行 ID。
    ///   - stop: 停止点 S。
    ///   - approaches: 進入方向の点 E_i(添字が approachIndex)。
    /// - Returns: 規制。
    static func stop(id: Int64, at stop: MeterPoint, approaches: [MeterPoint]) -> RoadRegulation {
        let main = RoadRegulationGeometryPart(role: .main, coordinates: [coordinate(stop)])
        let approachParts = approaches.map { RoadRegulationGeometryPart(role: .approach, coordinates: [coordinate($0)]) }
        return regulation(id: id, kind: .stop, speedLimitKph: nil, oneWayOrder: nil, parts: [main] + approachParts)
    }

    /// 責務: 最高速度の区域(114)を、閉じた輪で作ります。
    /// - Parameters:
    ///   - id: 規制の行 ID。
    ///   - ring: 輪の点の列(先頭の点を末尾に足して閉じる)。
    /// - Returns: 規制。
    static func zone(id: Int64, ring: [MeterPoint]) -> RoadRegulation {
        let closed = (ring + ring.prefix(1)).map(coordinate)
        return regulation(
            id: id,
            kind: .speedLimitZone,
            speedLimitKph: 30,
            oneWayOrder: nil,
            parts: [RoadRegulationGeometryPart(role: .main, coordinates: closed)]
        )
    }

    /// 責務: 条件なし・片側両側不明の規制を組み立てます。
    /// - Parameters:
    ///   - id: 規制の行 ID。
    ///   - kind: 種別。
    ///   - speedLimitKph: 最高速度。
    ///   - oneWayOrder: 一方通行の座標の並び方。
    ///   - parts: 形状の区間。
    /// - Returns: 規制。
    private static func regulation(
        id: Int64,
        kind: RoadRegulationKind,
        speedLimitKph: Int?,
        oneWayOrder: RoadRegulationOneWayOrder?,
        parts: [RoadRegulationGeometryPart]
    ) -> RoadRegulation {
        RoadRegulation(
            id: RoadRegulationID(rawValue: id),
            datasetID: RoadRegulationDatasetID(rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5))),
            uniqueKey: "test-\(id)",
            kind: kind,
            speedLimitKph: speedLimitKph,
            side: nil,
            oneWayOrder: oneWayOrder,
            perimeterRoadIncluded: nil,
            conditions: .unconditional,
            geometry: RoadRegulationGeometry(parts: parts)
        )
    }
}
