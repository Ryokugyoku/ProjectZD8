import Foundation
@testable import ProjectZD8

/// matcher と記録器のテストで、時刻を指定した軌跡の点を作り、点を1つずつ matcher へ流して各歩の結果を集める補助です。
///
/// 位置は `RoadRegulationMeterRegulationFactory` と同じ原点から東へ x m・北へ y m、実時間は基準 + 時刻軸の秒です。
enum RoadRegulationMatcherTestDriver {
    /// 責務: 時刻軸の秒を指定して軌跡の点を作ります。
    /// - Parameters:
    ///   - sequence: 連番。
    ///   - time: 時刻軸の秒。
    ///   - x: 東への距離(m)。
    ///   - y: 北への距離(m)。
    ///   - course: GPS の進行方向(度)。`nil` なら進行方向なし。
    ///   - speed: GPS の速さ(m/s)。
    /// - Returns: 軌跡の点(精度 5 m)。
    static func point(sequence: Int64, time: TimeInterval, x: Double, y: Double, course: Double? = 90, speed: Double? = 5)
        -> RoadRegulationTrackPoint {
        RoadRegulationTrackPoint(
            sequence: sequence,
            time: time,
            observedAt: RoadRegulationMeterTrackPointFactory.referenceDate.addingTimeInterval(time),
            coordinate: RoadRegulationMeterRegulationFactory.coordinate((x: x, y: y)),
            horizontalAccuracyMeters: 5,
            courseDegrees: course,
            gpsSpeedMetersPerSecond: speed
        )
    }

    /// 責務: (x, y) の列から、連番 = 時刻軸の秒 = 添字 + `firstSequence` の点の列を作ります。
    /// - Parameters:
    ///   - positions: 点の位置(メートル単位)。
    ///   - firstSequence: 最初の点の連番。
    ///   - course: GPS の進行方向(度)。
    /// - Returns: 1 秒間隔の点の列。
    static func track(
        _ positions: [RoadRegulationMeterRegulationFactory.MeterPoint],
        firstSequence: Int64 = 0,
        course: Double? = 90
    ) -> [RoadRegulationTrackPoint] {
        positions.enumerated().map { index, position in
            let sequence = firstSequence + Int64(index)
            return point(sequence: sequence, time: TimeInterval(sequence), x: position.x, y: position.y, course: course)
        }
    }

    /// 責務: 点の印(時刻・連番・実時間)を作ります。
    /// - Parameter point: 軌跡の点。
    /// - Returns: 点の印。
    static func mark(of point: RoadRegulationTrackPoint) -> RoadRegulationTransitionMark {
        RoadRegulationTransitionMark(time: point.time, sequence: point.sequence, observedAt: point.observedAt)
    }

    /// 責務: 規制の一覧から、版の範囲の内か外かを決めた候補の文脈を作ります。
    /// - Parameters:
    ///   - regulations: 周辺の規制。
    ///   - inside: 版の範囲の内か。
    /// - Returns: 候補の文脈。
    static func context(_ regulations: [RoadRegulation], inside: Bool = true) -> RoadRegulationCandidateContext {
        RoadRegulationCandidateContext(regulations: regulations, isInsideDataCoverage: inside)
    }

    /// 責務: 点を順に matcher へ流し、各歩の結果を返します(点の数だけ回す)。
    /// - Parameters:
    ///   - points: 軌跡の点。
    ///   - context: 各点の候補の文脈。
    ///   - state: 始めの状態。
    ///   - matcher: 使う matcher。
    /// - Returns: 各点の歩の結果(点と同じ順)。
    static func run(
        _ points: [RoadRegulationTrackPoint],
        context: RoadRegulationCandidateContext,
        from state: RoadRegulationMatchState = .initial,
        matcher: RoadRegulationMatcher = RoadRegulationMatcher()
    ) -> [RoadRegulationMatchStep] {
        var current = state
        var steps: [RoadRegulationMatchStep] = []
        for point in points {
            let step = matcher.step(from: current, point: point, context: context)
            steps.append(step)
            current = step.state
        }
        return steps
    }

    /// 責務: 全歩の変化のうち、最高速度の経路の変化だけを順に返します。
    /// - Parameter steps: 歩の結果。
    /// - Returns: 最高速度の経路の変化。
    static func speedLimitChanges(_ steps: [RoadRegulationMatchStep]) -> [RoadRegulationChange] {
        steps.flatMap(\.changes).filter { change in
            if case .speedLimitChanged = change { return true }
            return false
        }
    }

    /// 責務: 全歩の変化のうち、一時停止の開始・到達・打ち切りだけを順に返します。
    /// - Parameter steps: 歩の結果。
    /// - Returns: 一時停止の変化。
    static func stopChanges(_ steps: [RoadRegulationMatchStep]) -> [RoadRegulationChange] {
        steps.flatMap(\.changes).filter { change in
            switch change {
            case .stopApproachStarted, .stopReached, .stopApproachAbandoned: true
            default: false
            }
        }
    }

    /// 責務: 全歩の変化のうち、記録の空白だけを順に返します。
    /// - Parameter steps: 歩の結果。
    /// - Returns: 記録の空白の変化。
    static func gapChanges(_ steps: [RoadRegulationMatchStep]) -> [RoadRegulationChange] {
        steps.flatMap(\.changes).filter { change in
            if case .trackGap = change { return true }
            return false
        }
    }
}
