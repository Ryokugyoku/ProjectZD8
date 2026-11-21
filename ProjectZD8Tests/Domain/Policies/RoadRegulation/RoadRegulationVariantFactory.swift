import Foundation
@testable import ProjectZD8

/// 経路・matcher のテストで、`RoadRegulationMeterRegulationFactory` が作った規制の一部の項目
/// (種別・最高速度・片側両側・条件・形状)だけを差し替えた規制を作る補助です。
enum RoadRegulationVariantFactory {
    /// 責務: 元の規制の片側・両側の別だけを差し替えます。
    /// - Parameters:
    ///   - base: 元の規制。
    ///   - side: 新しい片側・両側の別。
    /// - Returns: 差し替えた規制。
    static func withSide(_ base: RoadRegulation, _ side: RoadRegulationSideCode) -> RoadRegulation {
        copy(base, side: side)
    }

    /// 責務: 元の規制の対象・除外の条件だけを差し替えます。
    /// - Parameters:
    ///   - base: 元の規制。
    ///   - conditions: 新しい条件。
    /// - Returns: 差し替えた規制。
    static func withConditions(_ base: RoadRegulation, _ conditions: RoadRegulationConditions) -> RoadRegulation {
        copy(base, conditions: conditions)
    }

    /// 責務: 元の規制の最高速度だけを差し替えます。
    /// - Parameters:
    ///   - base: 元の規制。
    ///   - speedLimitKph: 新しい最高速度。
    /// - Returns: 差し替えた規制。
    static func withSpeedLimit(_ base: RoadRegulation, _ speedLimitKph: Int?) -> RoadRegulation {
        copy(base, speedLimitKph: .some(speedLimitKph))
    }

    /// 責務: 元の規制に、除外の区間(点の列)を1つ足します。
    /// - Parameters:
    ///   - base: 元の規制。
    ///   - exclusion: 除外の点の列(メートル単位。閉じた輪にする時は先頭の点を末尾にも書く)。
    /// - Returns: 除外を足した規制。
    static func addingExclusion(_ base: RoadRegulation, _ exclusion: [RoadRegulationMeterRegulationFactory.MeterPoint]) -> RoadRegulation {
        let part = RoadRegulationGeometryPart(
            role: .exclusion,
            coordinates: exclusion.map(RoadRegulationMeterRegulationFactory.coordinate)
        )
        return copy(base, geometry: RoadRegulationGeometry(parts: base.geometry.parts + [part]))
    }

    /// 責務: 対象1の組だけに条件を持つ条件を作ります。
    /// - Parameter target: 対象1の組。
    /// - Returns: 条件。
    static func targetOnly(_ target: RoadRegulationConditionSet) -> RoadRegulationConditions {
        RoadRegulationConditions(targets: [target], exclusions: [])
    }

    /// 責務: 指定した項目だけを差し替えた規制を作ります(`nil` の引数は元の値を使う)。
    /// - Parameters:
    ///   - base: 元の規制。
    ///   - speedLimitKph: 新しい最高速度(`.some(nil)` で無しにする)。
    ///   - side: 新しい片側・両側の別。
    ///   - conditions: 新しい条件。
    ///   - geometry: 新しい形状。
    /// - Returns: 差し替えた規制。
    private static func copy(
        _ base: RoadRegulation,
        speedLimitKph: Int?? = nil,
        side: RoadRegulationSideCode? = nil,
        conditions: RoadRegulationConditions? = nil,
        geometry: RoadRegulationGeometry? = nil
    ) -> RoadRegulation {
        RoadRegulation(
            id: base.id,
            datasetID: base.datasetID,
            uniqueKey: base.uniqueKey,
            kind: base.kind,
            speedLimitKph: speedLimitKph ?? base.speedLimitKph,
            side: side ?? base.side,
            oneWayOrder: base.oneWayOrder,
            perimeterRoadIncluded: base.perimeterRoadIncluded,
            conditions: conditions ?? base.conditions,
            geometry: geometry ?? base.geometry
        )
    }
}
