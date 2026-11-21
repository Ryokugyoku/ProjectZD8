import Foundation
@testable import ProjectZD8

/// 記録器のテストで、点ごとの変化の列から matcher の歩の結果を組み立てて記録器へ流す補助です。
///
/// 歩の位置(いまの状態)は、それまでの変化の `to` で更新し、記録の空白では3つの経路を `pending` に戻します。
/// 歩の状態の「最後に使えた点」には、使った点ならその点の印を、無視した点(`ignoredIndices`)なら直前の歩の値を入れます
/// (matcher は無視した点で状態を変えないため)。
struct RoadRegulationTraversalRecorderScript {
    /// 流す点です(連番の昇順)。
    let points: [RoadRegulationTrackPoint]
    /// 点の添字 → その歩で出す変化です。
    let changesByIndex: [Int: [RoadRegulationChange]]
    /// matcher が無視した(精度が悪いなど)とみなす点の添字です。
    var ignoredIndices: Set<Int> = []

    /// 責務: 全点を記録器へ流し、記録の結果を返します。
    /// - Returns: 区間の通過と一時停止の通過。
    func recordAll() -> (traversals: [RoadRegulationTraversal], stopPassages: [StopPassage]) {
        var recorder = RoadRegulationTraversalRecorder()
        var position = RoadRegulationPosition(speedLimit: .pending, oneWay: .pending, slowDown: .pending, activeStopApproaches: [])
        var lastUsable: RoadRegulationTransitionMark?
        for (index, point) in points.enumerated() {
            let ignored = ignoredIndices.contains(index)
            let changes = ignored ? [] : changesByIndex[index] ?? []
            position = changes.reduce(position, Self.apply)
            if !ignored { lastUsable = RoadRegulationMatcherTestDriver.mark(of: point) }
            recorder.record(RoadRegulationMatchStep(state: Self.state(lastUsable: lastUsable), position: position, changes: changes), point: point)
        }
        return recorder.finish()
    }

    /// 責務: 最後に使えた点だけを持つ matcher の状態を作ります(記録器はほかの項目を読みません)。
    /// - Parameter lastUsable: 最後に使えた点の印。
    /// - Returns: matcher の状態。
    static func state(lastUsable: RoadRegulationTransitionMark?) -> RoadRegulationMatchState {
        RoadRegulationMatchState(
            heading: .initial,
            speedLimit: RoadRegulationStatusConfirmation(initial: .pending),
            oneWay: RoadRegulationStatusConfirmation(initial: .pending),
            slowDown: RoadRegulationStatusConfirmation(initial: .pending),
            stops: .initial,
            lastUsableMark: lastUsable
        )
    }

    /// 責務: 時刻軸の秒を指定した点の列を作ります(連番は添字)。
    /// - Parameter times: 各点の時刻軸の秒。
    /// - Returns: 東へ 5 m ずつ進む点の列。
    static func points(times: [TimeInterval]) -> [RoadRegulationTrackPoint] {
        times.enumerated().map { index, time in
            RoadRegulationMatcherTestDriver.point(sequence: Int64(index), time: time, x: Double(index) * 5, y: 0)
        }
    }

    /// 責務: 1つの変化で位置(いまの状態)を更新します。
    /// - Parameters:
    ///   - position: 直前の位置。
    ///   - change: 変化。
    /// - Returns: 更新した位置。
    private static func apply(_ position: RoadRegulationPosition, _ change: RoadRegulationChange) -> RoadRegulationPosition {
        switch change {
        case .speedLimitChanged(_, let to, _):
            RoadRegulationPosition(speedLimit: to, oneWay: position.oneWay, slowDown: position.slowDown, activeStopApproaches: [])
        case .oneWayChanged(_, let to, _):
            RoadRegulationPosition(speedLimit: position.speedLimit, oneWay: to, slowDown: position.slowDown, activeStopApproaches: [])
        case .slowDownChanged(_, let to, _):
            RoadRegulationPosition(speedLimit: position.speedLimit, oneWay: position.oneWay, slowDown: to, activeStopApproaches: [])
        case .trackGap:
            RoadRegulationPosition(speedLimit: .pending, oneWay: .pending, slowDown: .pending, activeStopApproaches: [])
        case .stopApproachStarted, .stopReached, .stopApproachAbandoned:
            position
        }
    }
}
