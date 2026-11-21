import XCTest
@testable import ProjectZD8

/// `RoadRegulationMatcher.step` の、位置の空白(10 秒を超えて使える点が無い)の扱いと、一時停止の開始・到達の変化を検証します
/// (設計書 §3.5「最初に」と「一時停止」、TB7)。
///
/// 空白の境界は、直前の点から 9.5 秒と 10.5 秒で確かめます。
/// 一時停止は、停止点 S = (0, 0)、進入方向の点 E = (0, −15)(北向きに近づく)です。
@MainActor
final class RoadRegulationMatcherGapTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Driver = RoadRegulationMatcherTestDriver

    /// 一時停止の接近の鍵です。
    private let stopKey = StopApproachKey(regulationID: RoadRegulationID(rawValue: 8), approachIndex: 0)

    /// 責務: 東西の道(最高速度 40)を作ります。
    private func eastRoad() -> RoadRegulation {
        Shapes.line(id: 1, points: [(x: -1_000, y: 0), (x: -500, y: 0), (x: 0, y: 0), (x: 500, y: 0), (x: 1_000, y: 0)])
    }

    /// 責務: 停止点 (0, 0)・進入方向 (0, −15) の一時停止を作ります。
    private func stop() -> RoadRegulation {
        Shapes.stop(id: 8, at: (x: 0, y: 0), approaches: [(x: 0, y: -15)])
    }

    /// 責務: 1 秒ごとに東へ 5 m の6点(時刻 0〜5)の後に、時刻を指定した点を続けた軌跡を作ります。
    private func trackWithGap(nextTimes: [TimeInterval]) -> [RoadRegulationTrackPoint] {
        let head = Driver.track((0..<6).map { (x: Double($0) * 5, y: 0) })
        let tail = nextTimes.enumerated().map { index, time in
            Driver.point(sequence: Int64(6 + index), time: time, x: 30 + Double(index) * 5, y: 0)
        }
        return head + tail
    }

    /// 責務: 道に乗った最高速度の状態を返します。
    private var regulated: SpeedLimitStatus { .regulated(RoadRegulationID(rawValue: 1), limitKph: 40) }

    /// 責務: 10.5 秒空くと `trackGap`(直前の使える点の印)を出し、最高速度の経路が `pending` に戻ることを確かめます。
    func testGapLongerThanLimitEmitsTrackGapAndResetsToPending() {
        let points = trackWithGap(nextTimes: [15.5, 16.5, 17.5])
        let steps = Driver.run(points, context: Driver.context([eastRoad()]))

        XCTAssertEqual(steps[5].position.speedLimit, regulated)
        XCTAssertEqual(steps[5].position.oneWay, OneWayChannelStatus.none)
        XCTAssertEqual(Driver.gapChanges(steps), [.trackGap(lastUsable: Driver.mark(of: points[5]))])
        XCTAssertEqual(steps[6].changes, [.trackGap(lastUsable: Driver.mark(of: points[5]))], "経路ごとの変化は出しません")
        XCTAssertEqual(steps[6].position.speedLimit, .pending)
        XCTAssertEqual(steps[6].position.oneWay, .pending)
        XCTAssertEqual(steps[6].position.slowDown, .pending)
        XCTAssertEqual(steps[7].position.speedLimit, .pending)
    }

    /// 責務: ちょうど 10 秒の間隔は空白とせず、11 秒は空白とすることを確かめます。
    func testGapBoundaryAtTenSeconds() {
        let exact = Driver.run(trackWithGap(nextTimes: [15]), context: Driver.context([eastRoad()]))
        let over = Driver.run(trackWithGap(nextTimes: [16]), context: Driver.context([eastRoad()]))
        XCTAssertEqual(Driver.gapChanges(exact), [])
        XCTAssertEqual(Driver.gapChanges(over).count, 1)
    }

    /// 責務: 精度が 50 m を超える点と、時刻が有限でない点は、状態を変えず変化も出さずに無視することを確かめます。
    func testUnusablePointsAreIgnoredWithoutChangingState() throws {
        let points = Driver.track((0..<3).map { (x: Double($0) * 5, y: 0) })
        let steps = Driver.run(points, context: Driver.context([eastRoad()]))
        let state = try XCTUnwrap(steps.last?.state)
        let inaccurate = RoadRegulationTrackPoint(
            sequence: 3, time: 3, observedAt: RoadRegulationMeterTrackPointFactory.referenceDate.addingTimeInterval(3),
            coordinate: RoadRegulationMeterRegulationFactory.coordinate((x: 15, y: 300)), horizontalAccuracyMeters: 50.5,
            courseDegrees: 0, gpsSpeedMetersPerSecond: 5
        )
        let timeless = RoadRegulationTrackPoint(
            sequence: 4, time: .nan, observedAt: RoadRegulationMeterTrackPointFactory.referenceDate,
            coordinate: RoadRegulationMeterRegulationFactory.coordinate((x: 15, y: 300)), horizontalAccuracyMeters: 5,
            courseDegrees: 0, gpsSpeedMetersPerSecond: 5
        )
        let matcher = RoadRegulationMatcher()

        for point in [inaccurate, timeless] {
            let step = matcher.step(from: state, point: point, context: Driver.context([eastRoad()]))
            XCTAssertEqual(step.state, state, "sequence=\(point.sequence)")
            XCTAssertEqual(step.changes, [], "sequence=\(point.sequence)")
        }
    }

    /// 責務: 空白の後は、空白の直後の点から数え直して3点目で確定し、since が空白の直後の点になることを確かめます。
    func testStatusIsConfirmedAgainFromFirstPointAfterGap() {
        let points = trackWithGap(nextTimes: [15.5, 16.5, 17.5])
        let steps = Driver.run(points, context: Driver.context([eastRoad()]))

        XCTAssertEqual(steps[8].position.speedLimit, regulated)
        XCTAssertEqual(
            Driver.speedLimitChanges([steps[8]]),
            [.speedLimitChanged(from: .pending, to: regulated, since: Driver.mark(of: points[6]))]
        )
    }

    /// 責務: 9.5 秒の間隔は空白とせず、状態を保つことを確かめます。
    func testGapWithinLimitKeepsStatus() {
        let points = trackWithGap(nextTimes: [14.5])
        let steps = Driver.run(points, context: Driver.context([eastRoad()]))

        XCTAssertEqual(Driver.gapChanges(steps), [])
        XCTAssertEqual(steps[6].position.speedLimit, regulated)
        XCTAssertEqual(Driver.speedLimitChanges(steps).count, 1)
    }

    /// 責務: 北向きに y = −62 から 5 m ごとに走ると、y = −37 で開始し y = −2 で到達し、それぞれ1回だけ出ることを確かめます。
    func testStopApproachStartsAndReachesOnce() {
        let points = Driver.track((0..<18).map { (x: 0, y: -62 + Double($0) * 5) }, course: 0)
        let steps = Driver.run(points, context: Driver.context([stop()]))
        let passage = StopPassage(
            key: stopKey,
            approachStarted: Driver.mark(of: points[5]),
            reached: Driver.mark(of: points[12]),
            applicability: .applies,
            interruptedByGap: false
        )

        XCTAssertEqual(Driver.stopChanges(steps), [.stopApproachStarted(stopKey, Driver.mark(of: points[5])), .stopReached(passage)])
        XCTAssertEqual(steps[4].position.activeStopApproaches, [])
        XCTAssertEqual(steps[8].position.activeStopApproaches, [stopKey])
        XCTAssertEqual(steps[12].position.activeStopApproaches, [])
    }

    /// 責務: 接近の途中で空白になると、`trackGap` と、`interruptedByGap = true` の到達を出して接近を打ち切ることを確かめます。
    func testGapInterruptsActiveStopApproach() {
        let points = [
            Driver.point(sequence: 0, time: 0, x: 0, y: -30, course: 0),
            Driver.point(sequence: 1, time: 1, x: 0, y: -25, course: 0),
            Driver.point(sequence: 2, time: 12.5, x: 0, y: 200, course: 0),
        ]
        let steps = Driver.run(points, context: Driver.context([stop()]))

        XCTAssertEqual(Driver.stopChanges([steps[0]]), [.stopApproachStarted(stopKey, Driver.mark(of: points[0]))])
        XCTAssertEqual(steps[1].position.activeStopApproaches, [stopKey])
        XCTAssertEqual(steps[2].changes.count, 2)
        XCTAssertEqual(steps[2].changes.first, .trackGap(lastUsable: Driver.mark(of: points[1])), "空白が先に並びます")
        let reached = steps[2].changes.compactMap { change -> StopPassage? in
            if case .stopReached(let passage) = change { return passage }
            return nil
        }
        XCTAssertEqual(reached.count, 1)
        XCTAssertEqual(reached.first?.key, stopKey)
        XCTAssertEqual(reached.first?.approachStarted, Driver.mark(of: points[0]))
        XCTAssertEqual(reached.first?.interruptedByGap, true)
        XCTAssertEqual(steps[2].position.activeStopApproaches, [])
    }
}
