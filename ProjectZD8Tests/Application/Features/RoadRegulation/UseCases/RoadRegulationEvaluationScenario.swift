import Foundation
@testable import ProjectZD8

/// evaluator のテストで、1本の東向きの軌跡の上に4種類の規制を順に置いた場面を作る補助です。
///
/// 原点(北緯26.2度・東経127.7度)から東へ x m の位置に、1 秒ごとに 10 m 進む点(連番 = 時刻軸の秒 = x / 10、
/// 進行方向 90 度・GPS 10 m/s・精度 5 m)を x = 0〜1,200 m に置きます。規制は次のとおりです。
/// - 最高速度の区間(112、行 ID 1、40 km/h): x = 0〜400
/// - 徐行(61、行 ID 2): x = 500〜700
/// - 一方通行(11、行 ID 3): 座標の並び (1,000 → 800)、並び2(通行できる向きは西)。東向きに走るので逆方向
/// - 一時停止(63、行 ID 4): 停止点 x = 1,153、進入方向の点 x = 1,138(東向きに近づく)
enum RoadRegulationEvaluationScenario {
    /// 軌跡の点の数です(x = 0〜1,200 m)。
    static let pointCount = 121
    /// 場面で使う版の参照です。
    nonisolated static let datasets = [
        RoadRegulationDatasetReference(prefecture: RoadRegulationTestValues.prefecture(47), dataMonth: RoadRegulationTestValues.month(2026, 8)),
    ]

    /// 責務: 場面の4つの規制を作ります。
    /// - Returns: 規制(行 ID 1〜4)。
    static func regulations() -> [RoadRegulation] {
        typealias Shapes = RoadRegulationMeterRegulationFactory
        return [
            Shapes.line(id: 1, points: [(x: 0, y: 0), (x: 400, y: 0)], speedLimitKph: 40),
            Shapes.line(id: 2, kind: .slowDown, points: [(x: 500, y: 0), (x: 700, y: 0)], speedLimitKph: nil),
            Shapes.oneWay(id: 3, points: [(x: 1_000, y: 0), (x: 800, y: 0)], order: .permittedDirection),
            Shapes.stop(id: 4, at: (x: 1_153, y: 0), approaches: [(x: 1_138, y: 0)]),
        ]
    }

    /// 責務: 東向きに 10 m/s で進む軌跡を作ります。
    /// - Parameter count: 点の数。
    /// - Returns: 連番 0, 1, 2, … の点。
    static func track(count: Int = pointCount) -> [RoadRegulationTrackPoint] {
        (0..<count).map { index in
            RoadRegulationMeterTrackPointFactory.point(sequence: Int64(index), x: Double(index) * 10, y: 0, course: 90, speed: 10)
        }
    }

    /// 責務: 整数秒ごとに同じ車速を置き、指定した秒だけ別の車速にした時系列を作ります。
    /// - Parameters:
    ///   - kph: 既定の車速(km/h)。
    ///   - overrides: 時刻の秒 → 車速。
    ///   - count: サンプルの数(時刻 0〜count−1)。
    /// - Returns: 車速の時系列。
    static func speeds(_ kph: Double, overrides: [Int: Double] = [:], count: Int = pointCount) -> VehicleSpeedTimeline {
        VehicleSpeedTimeline(samples: (0..<count).map { VehicleSpeedSample(time: TimeInterval($0), kph: overrides[$0] ?? kph) })
    }

    /// 責務: 原点から東へ west〜east m・北へ south〜north m の範囲の外接矩形を作ります。
    /// - Parameters:
    ///   - west: 西端(m)。
    ///   - east: 東端(m)。
    ///   - south: 南端(m)。
    ///   - north: 北端(m)。
    /// - Returns: 外接矩形。
    static func coverage(west: Double = -500, east: Double = 2_000, south: Double = -500, north: Double = 500) -> GeoBoundingBox {
        let corners = [
            RoadRegulationMeterRegulationFactory.coordinate((x: west, y: south)),
            RoadRegulationMeterRegulationFactory.coordinate((x: east, y: north)),
        ]
        guard let box = GeoBoundingBox(enclosing: corners) else { preconditionFailure("テストの外接矩形を作れません") }
        return box
    }

    /// 責務: 場面の規制と軌跡で evaluator を動かします。
    /// - Parameters:
    ///   - speeds: 車速の時系列。
    ///   - track: 軌跡。
    ///   - regulations: 規制。
    ///   - coverage: 版の範囲。
    ///   - droppedPointCount: 捨てた点の数。
    ///   - timeAxis: 時刻の軸。
    /// - Returns: 1セッションの判定の結果。
    static func evaluate(
        speeds: VehicleSpeedTimeline,
        track: [RoadRegulationTrackPoint] = track(),
        regulations: [RoadRegulation] = regulations(),
        coverage: [GeoBoundingBox] = [coverage()],
        droppedPointCount: Int = 0,
        timeAxis: RoadRegulationTimeAxis = .monotonic
    ) -> SessionRoadRegulationReport {
        SessionRoadRegulationEvaluator().evaluate(
            track: track,
            droppedPointCount: droppedPointCount,
            speeds: speeds,
            index: RoadRegulationSpatialIndex(regulations: regulations),
            coverage: coverage,
            timeAxis: timeAxis,
            datasets: datasets
        )
    }
}
