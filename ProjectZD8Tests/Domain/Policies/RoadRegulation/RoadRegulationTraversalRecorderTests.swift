import XCTest
@testable import ProjectZD8

/// `RoadRegulationTraversalRecorder` が、経路の状態の変化の列から区間の通過 [since_i, since_{i+1} の直前の点] と
/// 一時停止の通過を組み立てることを検証します(設計書 §3.5「記録」、TB7)。
///
/// 記録しないもの: `pending`、一方通行・徐行の `none`。終わりの理由は、次の変化 → `changed`、空白 → `trackGap`、最後の点 → `trackEnded`。
/// 点の時刻は 1.5 秒間隔(空白の後は 30 秒進める)にして、印が点そのものから取られることも確かめます。
@MainActor
final class RoadRegulationTraversalRecorderTests: XCTestCase {
    private typealias Script = RoadRegulationTraversalRecorderScript
    private typealias Driver = RoadRegulationMatcherTestDriver

    /// 規制 A・B の状態です。
    private let regulatedA = SpeedLimitStatus.regulated(RoadRegulationID(rawValue: 1), limitKph: 40)
    private let regulatedB = SpeedLimitStatus.regulated(RoadRegulationID(rawValue: 2), limitKph: 60)

    /// 責務: 1.5 秒間隔の `count` 点を作ります。
    private func points(_ count: Int) -> [RoadRegulationTrackPoint] {
        Script.points(times: (0..<count).map { Double($0) * 1.5 })
    }

    /// 責務: 区間の通過を作ります。
    private func traversal(
        _ status: RoadRegulationTraversalStatus,
        _ points: [RoadRegulationTrackPoint],
        _ range: ClosedRange<Int>,
        _ reason: RoadRegulationTraversalEndReason
    ) -> RoadRegulationTraversal {
        RoadRegulationTraversal(
            status: status,
            start: Driver.mark(of: points[range.lowerBound]),
            end: Driver.mark(of: points[range.upperBound]),
            endReason: reason
        )
    }

    /// 責務: 最高速度の経路の通過だけを返します。
    private func speedLimitOnly(_ traversals: [RoadRegulationTraversal]) -> [RoadRegulationTraversal] {
        traversals.filter { if case .speedLimit = $0.status { true } else { false } }
    }

    /// 責務: 一方通行の経路の通過だけを返します。
    private func oneWayOnly(_ traversals: [RoadRegulationTraversal]) -> [RoadRegulationTraversal] {
        traversals.filter { if case .oneWay = $0.status { true } else { false } }
    }

    /// 責務: 徐行の経路の通過だけを返します。
    private func slowDownOnly(_ traversals: [RoadRegulationTraversal]) -> [RoadRegulationTraversal] {
        traversals.filter { if case .slowDown = $0.status { true } else { false } }
    }

    /// 責務: 3つの経路が最初に確定する変化(最高速度は `to`、ほかは `none`)を作ります。
    private func initialChanges(speedLimit to: SpeedLimitStatus, since: RoadRegulationTransitionMark) -> [RoadRegulationChange] {
        [
            .speedLimitChanged(from: .pending, to: to, since: since),
            .oneWayChanged(from: .pending, to: OneWayChannelStatus.none, since: since),
            .slowDownChanged(from: .pending, to: SlowDownChannelStatus.none, since: since),
        ]
    }

    /// 責務: 何も記録しなければ、区間も一時停止も空になることを確かめます。
    func testEmptyRecorderFinishesEmpty() {
        var recorder = RoadRegulationTraversalRecorder()
        let result = recorder.finish()
        XCTAssertEqual(result.traversals, [])
        XCTAssertEqual(result.stopPassages, [])
    }

    /// 責務: `finish()` の後は記録器が空に戻り、もう一度 `finish()` しても前の区間を返さないことを確かめます。
    func testFinishResetsRecorder() {
        let track = points(4)
        var recorder = RoadRegulationTraversalRecorder()
        let changes: [RoadRegulationChange] = [.speedLimitChanged(from: .pending, to: regulatedA, since: Driver.mark(of: track[0]))]
        for (index, point) in track.enumerated() {
            let status: SpeedLimitStatus = index >= 2 ? regulatedA : .pending
            let position = RoadRegulationPosition(speedLimit: status, oneWay: .pending, slowDown: .pending, activeStopApproaches: [])
            let state = Script.state(lastUsable: Driver.mark(of: point))
            let step = RoadRegulationMatchStep(state: state, position: position, changes: index == 2 ? changes : [])
            recorder.record(step, point: point)
        }
        let first = recorder.finish()
        let second = recorder.finish()
        XCTAssertEqual(first.traversals, [traversal(.speedLimit(regulatedA), track, 0...3, .trackEnded)])
        XCTAssertEqual(second.traversals, [])
        XCTAssertEqual(second.stopPassages, [])
    }

    /// 責務: matcher が無視した点(状態の「最後に使えた点」がその点でない歩)は記録せず、最後の使える点で閉じることを確かめます。
    func testIgnoredTrailingPointIsNotRecorded() {
        let track = points(6)
        var script = Script(points: track, changesByIndex: [2: initialChanges(speedLimit: regulatedA, since: Driver.mark(of: track[0]))])
        script.ignoredIndices = [5]
        XCTAssertEqual(script.recordAll().traversals, [traversal(.speedLimit(regulatedA), track, 0...4, .trackEnded)])
    }

    /// 責務: 状態が `pending` のまま終わると、区間を記録しないことを確かめます。
    func testPendingIsNotRecorded() {
        let result = Script(points: points(5), changesByIndex: [:]).recordAll()
        XCTAssertEqual(result.traversals, [])
    }

    /// 責務: 開いたままの区間は最後の点で `trackEnded` として閉じ、一方通行・徐行の `none` は記録しないことを確かめます。
    func testOpenSectionClosesAtLastPointAsTrackEnded() {
        let track = points(10)
        let script = Script(points: track, changesByIndex: [2: initialChanges(speedLimit: regulatedA, since: Driver.mark(of: track[0]))])
        let result = script.recordAll()
        XCTAssertEqual(result.traversals, [traversal(.speedLimit(regulatedA), track, 0...9, .trackEnded)])
        XCTAssertEqual(result.stopPassages, [])
    }

    /// 責務: 変化で前の区間を since の直前の点で `changed` として閉じ、次の区間が since から始まる(隙間も重なりもない)ことを確かめます。
    func testChangeClosesPreviousSectionAtPointBeforeSince() {
        let track = points(10)
        let script = Script(points: track, changesByIndex: [
            2: initialChanges(speedLimit: regulatedA, since: Driver.mark(of: track[0])),
            7: [.speedLimitChanged(from: regulatedA, to: regulatedB, since: Driver.mark(of: track[5]))],
        ])
        let speed = speedLimitOnly(script.recordAll().traversals)

        XCTAssertEqual(speed, [
            traversal(.speedLimit(regulatedA), track, 0...4, .changed),
            traversal(.speedLimit(regulatedB), track, 5...9, .trackEnded),
        ])
        XCTAssertEqual(speed.last?.start.sequence, (speed.first?.end.sequence ?? -9) + 1)
    }

    /// 責務: `unregulated` と `undeterminable` も区間として記録することを確かめます(最高速度の経路)。
    func testUnregulatedAndUndeterminableAreRecorded() {
        let track = points(10)
        let coarse = SpeedLimitStatus.undeterminable(.coarseGeometry, RoadRegulationID(rawValue: 3))
        let script = Script(points: track, changesByIndex: [
            2: initialChanges(speedLimit: regulatedA, since: Driver.mark(of: track[0])),
            5: [.speedLimitChanged(from: regulatedA, to: .unregulated, since: Driver.mark(of: track[3]))],
            8: [.speedLimitChanged(from: .unregulated, to: coarse, since: Driver.mark(of: track[6]))],
        ])
        XCTAssertEqual(speedLimitOnly(script.recordAll().traversals), [
            traversal(.speedLimit(regulatedA), track, 0...2, .changed),
            traversal(.speedLimit(.unregulated), track, 3...5, .changed),
            traversal(.speedLimit(coarse), track, 6...9, .trackEnded),
        ])
    }

    /// 責務: 一方通行は `on` の区間だけを記録し、その前後の `none` は記録しないことを確かめます。
    func testOneWayRecordsOnlyOnSections() {
        let track = points(10)
        let reverse = OneWayChannelStatus.on(RoadRegulationID(rawValue: 4), .reverse)
        let script = Script(points: track, changesByIndex: [
            2: initialChanges(speedLimit: .unregulated, since: Driver.mark(of: track[0])),
            5: [.oneWayChanged(from: OneWayChannelStatus.none, to: reverse, since: Driver.mark(of: track[3]))],
            8: [.oneWayChanged(from: reverse, to: OneWayChannelStatus.none, since: Driver.mark(of: track[6]))],
        ])
        XCTAssertEqual(oneWayOnly(script.recordAll().traversals), [traversal(.oneWay(reverse), track, 3...5, .changed)])
    }

    /// 責務: 徐行は `on` と `undeterminable` を記録し、`none` は記録しないことを確かめます。
    func testSlowDownRecordsOnAndUndeterminable() {
        let track = points(10)
        let on = SlowDownChannelStatus.on(RoadRegulationID(rawValue: 5))
        let unknown = SlowDownChannelStatus.undeterminable(.conditionUnknown, RoadRegulationID(rawValue: 6))
        let script = Script(points: track, changesByIndex: [
            2: initialChanges(speedLimit: .unregulated, since: Driver.mark(of: track[0])),
            4: [.slowDownChanged(from: SlowDownChannelStatus.none, to: on, since: Driver.mark(of: track[2]))],
            7: [.slowDownChanged(from: on, to: unknown, since: Driver.mark(of: track[5]))],
        ])
        XCTAssertEqual(slowDownOnly(script.recordAll().traversals), [
            traversal(.slowDown(on), track, 2...4, .changed),
            traversal(.slowDown(unknown), track, 5...9, .trackEnded),
        ])
    }

    /// 責務: 空白で、開いている区間を直前の使える点で `trackGap` として閉じ、空白の後は新しい区間として始めることを確かめます。
    func testTrackGapClosesOpenSectionsAtLastUsablePoint() {
        let track = Script.points(times: [0, 1.5, 3, 4.5, 6, 36, 37.5, 39, 40.5, 42])
        let permitted = OneWayChannelStatus.on(RoadRegulationID(rawValue: 4), .permitted)
        let script = Script(points: track, changesByIndex: [
            2: initialChanges(speedLimit: regulatedA, since: Driver.mark(of: track[0])),
            3: [.oneWayChanged(from: OneWayChannelStatus.none, to: permitted, since: Driver.mark(of: track[1]))],
            5: [.trackGap(lastUsable: Driver.mark(of: track[4]))],
            7: [.speedLimitChanged(from: .pending, to: regulatedA, since: Driver.mark(of: track[5]))],
        ])
        let traversals = script.recordAll().traversals

        XCTAssertEqual(speedLimitOnly(traversals), [
            traversal(.speedLimit(regulatedA), track, 0...4, .trackGap),
            traversal(.speedLimit(regulatedA), track, 5...9, .trackEnded),
        ])
        XCTAssertEqual(oneWayOnly(traversals), [traversal(.oneWay(permitted), track, 1...4, .trackGap)])
    }

    /// 責務: 一時停止の到達を出た順に集め(開始・到達の印と打ち切りの印を保つ)、開始と打ち切りだけでは数えないことを確かめます。
    func testStopPassagesAreCollectedInOrder() {
        let track = points(8)
        let first = StopPassage(
            key: StopApproachKey(regulationID: RoadRegulationID(rawValue: 7), approachIndex: 0),
            approachStarted: Driver.mark(of: track[0]),
            reached: Driver.mark(of: track[2]),
            applicability: .applies,
            interruptedByGap: false
        )
        let second = StopPassage(
            key: StopApproachKey(regulationID: RoadRegulationID(rawValue: 9), approachIndex: 1),
            approachStarted: Driver.mark(of: track[4]),
            reached: Driver.mark(of: track[6]),
            applicability: .unknown,
            interruptedByGap: true
        )
        let abandoned = StopApproachKey(regulationID: RoadRegulationID(rawValue: 8), approachIndex: 0)
        let script = Script(points: track, changesByIndex: [
            0: [.stopApproachStarted(first.key, first.approachStarted)],
            2: [.stopReached(first)],
            3: [.stopApproachStarted(abandoned, Driver.mark(of: track[3]))],
            4: [.stopApproachAbandoned(abandoned), .stopApproachStarted(second.key, second.approachStarted)],
            6: [.stopReached(second)],
        ])
        XCTAssertEqual(script.recordAll().stopPassages, [first, second])
    }
}
