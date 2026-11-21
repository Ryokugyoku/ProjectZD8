import Foundation
@testable import ProjectZD8

/// 候補・向き・一時停止のテストで、`RoadRegulationMeterRegulationFactory` と同じ原点から東へ x m・北へ y m の位置に
/// 軌跡の点を作る補助です。時刻軸の秒は連番と同じ値にします。
enum RoadRegulationMeterTrackPointFactory {
    /// 実時間の基準(時刻軸の0秒)です。
    static let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    /// 責務: 東へ x m・北へ y m の位置に軌跡の点を作ります。
    /// - Parameters:
    ///   - sequence: 連番(時刻軸の秒にも使う)。
    ///   - x: 東への距離(m)。
    ///   - y: 北への距離(m)。
    ///   - accuracy: 水平精度(m)。
    ///   - course: GPS の進行方向(度)。
    ///   - speed: GPS の速さ(m/s)。
    /// - Returns: 軌跡の点。
    static func point(
        sequence: Int64 = 0,
        x: Double,
        y: Double,
        accuracy: Double = 5,
        course: Double? = nil,
        speed: Double? = nil
    ) -> RoadRegulationTrackPoint {
        RoadRegulationTrackPoint(
            sequence: sequence,
            time: TimeInterval(sequence),
            observedAt: referenceDate.addingTimeInterval(TimeInterval(sequence)),
            coordinate: RoadRegulationMeterRegulationFactory.coordinate((x: x, y: y)),
            horizontalAccuracyMeters: accuracy,
            courseDegrees: course,
            gpsSpeedMetersPerSecond: speed
        )
    }

    /// 責務: 連番 `sequence` の点の印(時刻 = 連番の秒、実時間 = 基準 + 連番の秒)を作ります。
    /// - Parameter sequence: 連番。
    /// - Returns: 点の印。
    static func mark(_ sequence: Int64) -> RoadRegulationTransitionMark {
        RoadRegulationTransitionMark(
            time: TimeInterval(sequence),
            sequence: sequence,
            observedAt: referenceDate.addingTimeInterval(TimeInterval(sequence))
        )
    }
}
