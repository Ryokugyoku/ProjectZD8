import Foundation
@testable import ProjectZD8

/// `StopApproachTracker` のテストで、メートル単位の経路(位置と進む向き)を1点ずつ追跡させ、各点の変化を集める補助です。
///
/// 経路の i 番目の点は連番 i(時刻 i 秒)になります。条件の判定はすべての規制・時刻で同じ値を返します。
struct StopApproachTrackerTestDriver {
    /// 経路の1点(東へ x m・北へ y m、進む向き、水平精度)です。
    typealias PathPoint = (x: Double, y: Double, heading: Double?, accuracy: Double)

    /// 追跡に渡す候補の規制。
    let candidates: [RoadRegulation]
    /// 条件の判定として返す値。
    var applicability: RegulationApplicability = .applies
    /// しきい値。
    var thresholds: RoadRegulationMatchingThresholds = .standard

    /// 責務: 東へ x m の直線上を、北へ y の列に沿って向き `heading` で進む経路を作ります。
    /// - Parameters:
    ///   - x: 東への距離(m)。
    ///   - ys: 北への距離(m)の列。
    ///   - heading: 進む向き(度)。
    ///   - accuracy: 水平精度(m)。
    /// - Returns: 経路。
    static func straight(x: Double, ys: [Double], heading: Double?, accuracy: Double = 5) -> [PathPoint] {
        ys.map { (x: x, y: $0, heading: heading, accuracy: accuracy) }
    }

    /// 責務: `from` から `through` まで `by` 刻みの値の列を作ります。
    /// - Parameters:
    ///   - from: 最初の値。
    ///   - through: 最後の値(含む)。
    ///   - by: 刻み。
    /// - Returns: 値の列。
    static func values(from: Double, through: Double, by: Double) -> [Double] {
        Array(stride(from: from, through: through, by: by))
    }

    /// 責務: 経路を先頭から1点ずつ追跡させ、最後の状態と各点の変化を返します。
    /// - Parameters:
    ///   - path: 経路。
    ///   - state: 最初の状態。
    ///   - firstSequence: 経路の最初の点の連番。
    /// - Returns: 最後の状態と、経路の点ごとの変化。
    func run(
        _ path: [PathPoint],
        from state: StopApproachTrackerState = .initial,
        firstSequence: Int64 = 0
    ) -> (state: StopApproachTrackerState, changesPerPoint: [[RoadRegulationChange]]) {
        let tracker = StopApproachTracker(thresholds: thresholds)
        let fixedApplicability = applicability
        var current = state
        var changesPerPoint: [[RoadRegulationChange]] = []
        for (offset, step) in path.enumerated() {
            let point = RoadRegulationMeterTrackPointFactory.point(
                sequence: firstSequence + Int64(offset),
                x: step.x,
                y: step.y,
                accuracy: step.accuracy
            )
            let result = tracker.step(current, point: point, heading: step.heading, candidates: candidates) { _, _ in fixedApplicability }
            current = result.0
            changesPerPoint.append(result.1)
        }
        return (current, changesPerPoint)
    }

    /// 責務: 経路を追跡させ、すべての変化を順に並べて返します。
    /// - Parameter path: 経路。
    /// - Returns: 変化の列。
    func changes(_ path: [PathPoint]) -> [RoadRegulationChange] {
        run(path).changesPerPoint.flatMap { $0 }
    }
}
