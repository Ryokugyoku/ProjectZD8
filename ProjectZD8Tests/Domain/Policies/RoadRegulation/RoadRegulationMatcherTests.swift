import XCTest
@testable import ProjectZD8

/// `RoadRegulationMatcher.step` を1点ずつ流した時の、状態の確定(3点の連続・since は連続の最初の点)、3つの経路、
/// 向きと条件の受け渡し、純粋さ(同じ入力 → 同じ結果、途中の状態から続けても同じ結果)を検証します(設計書 §3.5、TB7)。
///
/// 道は東西の線 (−1,000, 0)–(1,000, 0)(500 m ごとの点。最高速度 40)で、点は 1 秒ごとに東へ 5 m、進行方向 90 度・GPS 5 m/s です。
/// 道から 40 m 離れた点は、いま乗っている道の許容(精度 5 m で 17 + 10 = 27 m)の外になります。
@MainActor
final class RoadRegulationMatcherTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Driver = RoadRegulationMatcherTestDriver
    private typealias Variants = RoadRegulationVariantFactory

    /// 東西の道の行 ID です。
    private let roadID = RoadRegulationID(rawValue: 1)

    /// 責務: 東西の道(最高速度 40)を作ります。
    private func eastRoad() -> RoadRegulation {
        Shapes.line(id: 1, points: [(x: -1_000, y: 0), (x: -500, y: 0), (x: 0, y: 0), (x: 500, y: 0), (x: 1_000, y: 0)])
    }

    /// 責務: 添字 i の点を東へ 5i m、北へ `offsets` に含まれる添字なら 40 m(含まれなければ 0 m)に置いた点の列を作ります。
    private func eastboundTrack(count: Int, offRoad offsets: Set<Int> = []) -> [RoadRegulationTrackPoint] {
        Driver.track((0..<count).map { (x: Double($0) * 5, y: offsets.contains($0) ? 40 : 0) })
    }

    /// 責務: 道に乗った最高速度の状態を返します。
    private var regulated: SpeedLimitStatus { .regulated(roadID, limitKph: 40) }

    /// 責務: 2点目までは `pending` のまま変化を出さず、3点目で、連続の最初の点を since にして切り替わることを確かめます。
    func testFirstConfirmationNeedsThreeConsecutivePoints() {
        let points = eastboundTrack(count: 3)
        let steps = Driver.run(points, context: Driver.context([eastRoad()]))

        XCTAssertEqual(steps[0].position.speedLimit, .pending)
        XCTAssertEqual(steps[1].position.speedLimit, .pending)
        XCTAssertEqual(Driver.speedLimitChanges(Array(steps.prefix(2))), [])
        XCTAssertEqual(steps[2].position.speedLimit, regulated)
        XCTAssertEqual(
            Driver.speedLimitChanges([steps[2]]),
            [.speedLimitChanged(from: .pending, to: regulated, since: Driver.mark(of: points[0]))]
        )
    }

    /// 責務: 一方通行・徐行の経路も、候補が無ければ3点目で `pending` から `none` に確定し、
    /// 変化が「最高速度 → 一方通行 → 徐行」の順に並ぶことを確かめます。
    func testOtherChannelsConfirmNoneAfterThreePointsInChannelOrder() {
        let points = eastboundTrack(count: 3)
        let steps = Driver.run(points, context: Driver.context([eastRoad()]))
        let since = Driver.mark(of: points[0])
        XCTAssertEqual(steps[1].position.oneWay, .pending)
        XCTAssertEqual(steps[1].position.slowDown, .pending)
        XCTAssertEqual(steps[2].position.oneWay, OneWayChannelStatus.none)
        XCTAssertEqual(steps[2].position.slowDown, SlowDownChannelStatus.none)
        XCTAssertEqual(steps[2].changes, [
            .speedLimitChanged(from: .pending, to: regulated, since: since),
            .oneWayChanged(from: .pending, to: OneWayChannelStatus.none, since: since),
            .slowDownChanged(from: .pending, to: SlowDownChannelStatus.none, since: since),
        ])
    }

    /// 責務: 道から離れた点が2点だけなら、最高速度の状態は変わらないことを確かめます(揺らぎを抑える)。
    func testTwoPointExcursionDoesNotChangeStatus() {
        let points = eastboundTrack(count: 12, offRoad: [6, 7])
        let steps = Driver.run(points, context: Driver.context([eastRoad()]))

        XCTAssertEqual(
            Driver.speedLimitChanges(steps),
            [.speedLimitChanged(from: .pending, to: regulated, since: Driver.mark(of: points[0]))]
        )
        XCTAssertEqual(steps[6].position.speedLimit, regulated)
        XCTAssertEqual(steps[7].position.speedLimit, regulated)
    }

    /// 責務: 離れた点が3点続くと3点目で切り替わり、since が連続の最初の点になること、戻る時も同じであることを確かめます。
    func testThreePointExcursionChangesSinceFirstPointOfRun() {
        let points = eastboundTrack(count: 13, offRoad: [6, 7, 8])
        let steps = Driver.run(points, context: Driver.context([eastRoad()]))

        XCTAssertEqual(Driver.speedLimitChanges(steps), [
            .speedLimitChanged(from: .pending, to: regulated, since: Driver.mark(of: points[0])),
            .speedLimitChanged(from: regulated, to: .unregulated, since: Driver.mark(of: points[6])),
            .speedLimitChanged(from: .unregulated, to: regulated, since: Driver.mark(of: points[9])),
        ])
        XCTAssertEqual(Driver.speedLimitChanges([steps[8]]).count, 1)
        XCTAssertEqual(Driver.speedLimitChanges([steps[11]]).count, 1)
        XCTAssertEqual(steps[7].position.speedLimit, regulated)
        XCTAssertEqual(steps[8].position.speedLimit, .unregulated)
    }

    /// 責務: 一方通行(順方向)と徐行の区間を北向きに走ると、3点目でそれぞれ `on` に確定することを確かめます。
    func testOneWayAndSlowDownChannelsAreConfirmed() {
        let oneWay = Shapes.oneWay(id: 3, points: [(x: 0, y: -300), (x: 0, y: 300)], order: .permittedDirection)
        let slowDown = Shapes.line(id: 4, kind: .slowDown, points: [(x: 0, y: -300), (x: 0, y: 300)], speedLimitKph: nil)
        let points = Driver.track((0..<3).map { (x: 0, y: Double($0) * 5) }, course: 0)
        let steps = Driver.run(points, context: Driver.context([oneWay, slowDown]))
        let since = Driver.mark(of: points[0])
        let expectedOneWay = OneWayChannelStatus.on(RoadRegulationID(rawValue: 3), .permitted)
        let expectedSlowDown = SlowDownChannelStatus.on(RoadRegulationID(rawValue: 4))

        XCTAssertEqual(steps[2].position.oneWay, expectedOneWay)
        XCTAssertEqual(steps[2].position.slowDown, expectedSlowDown)
        XCTAssertTrue(steps[2].changes.contains(.oneWayChanged(from: .pending, to: expectedOneWay, since: since)))
        XCTAssertTrue(steps[2].changes.contains(.slowDownChanged(from: .pending, to: expectedSlowDown, since: since)))
    }

    /// 責務: 進行方向の無い点でも、移動から求めた向きで交差する道を除くことを確かめます(交差点の上で曖昧にならない)。
    func testHeadingFromDisplacementExcludesCrossingRoad() {
        let crossing = Shapes.line(id: 2, points: [(x: 0, y: -300), (x: 0, y: 300)], speedLimitKph: 60)
        let points = Driver.track([(x: -12, y: 0), (x: -6, y: 0), (x: 0, y: 0), (x: 6, y: 0), (x: 12, y: 0), (x: 18, y: 0)], course: nil)
        let steps = Driver.run(points, context: Driver.context([eastRoad(), crossing]))

        XCTAssertEqual(
            Driver.speedLimitChanges(steps),
            [.speedLimitChanged(from: .pending, to: regulated, since: Driver.mark(of: points[0]))]
        )
        XCTAssertEqual(steps[5].position.speedLimit, regulated)
    }

    /// 責務: 条件は点の実時間(東京で金曜 17:00 台)で評価され、時間帯が外れる道は候補にならないことを確かめます。
    func testConditionsAreEvaluatedAtObservedTime() {
        let morningOnly = Variants.withConditions(eastRoad(), Variants.targetOnly(RoadRegulationConditionSet(timeStart: "0700", timeEnd: "0900")))
        let evening = Variants.withConditions(eastRoad(), Variants.targetOnly(RoadRegulationConditionSet(timeStart: "1600", timeEnd: "1800")))
        let points = eastboundTrack(count: 3)

        XCTAssertEqual(Driver.run(points, context: Driver.context([morningOnly]))[2].position.speedLimit, .unregulated)
        XCTAssertEqual(Driver.run(points, context: Driver.context([evening]))[2].position.speedLimit, regulated)
    }

    /// 責務: 版の範囲の外では、3点目で `undeterminable(.outsideRegulationData, nil)` に確定することを確かめます。
    func testOutsideDataCoverageConfirmsUndeterminable() {
        let steps = Driver.run(eastboundTrack(count: 3), context: Driver.context([eastRoad()], inside: false))
        XCTAssertEqual(steps[2].position.speedLimit, .undeterminable(.outsideRegulationData, nil))
    }

    /// 責務: 同じ入力を2回流すと、各歩の結果(状態・位置・変化)がすべて一致することを確かめます(純粋)。
    func testSameInputGivesSameSteps() {
        let points = eastboundTrack(count: 13, offRoad: [6, 7, 8])
        let context = Driver.context([eastRoad()])
        let first = Driver.run(points, context: context)
        let second = Driver.run(points, context: context)
        XCTAssertEqual(first, second)
    }

    /// 責務: 途中の点の状態を取り出して続きから流しても、最初から流した結果と一致することを確かめます(走行中と走行後で同じ)。
    func testResumingFromIntermediateStateMatchesFullRun() {
        var points = eastboundTrack(count: 13, offRoad: [6, 7, 8])
        points.append(Driver.point(sequence: 13, time: 25, x: 70, y: 0))
        let context = Driver.context([eastRoad()])
        let full = Driver.run(points, context: context)

        for split in [1, 4, 7, 10, 13] {
            let head = Driver.run(Array(points.prefix(split)), context: context)
            guard let resumeState = head.last?.state else {
                XCTFail("途中の状態を取り出せません: \(split)")
                continue
            }
            let tail = Driver.run(Array(points.dropFirst(split)), context: context, from: resumeState)
            XCTAssertEqual(tail, Array(full.dropFirst(split)), "split=\(split)")
        }
    }
}
