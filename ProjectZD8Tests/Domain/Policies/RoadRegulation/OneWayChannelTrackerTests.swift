import XCTest
@testable import ProjectZD8

/// `OneWayChannelTracker` が、一方通行(11)の線の候補から順方向・逆方向・向き不明を観測することを検証します
/// (設計書 §3.5「一方通行の経路」、TB5)。
///
/// 道は南北の線 (0, −300)–(0, 300)(座標の並びの方位 0 度)で、点は (x, 0)・精度 5 m に置きます(許容 17 m、いま乗っている候補は 27 m)。
/// 通行できる向き p は、並び2(`.permittedDirection`)なら 0 度、並び1(`.prohibitedDirection`)なら 180 度です。
/// 角度の境界は 40 度・140 度の ±1 度、距離の境界は ±0.5 m で確かめます。
@MainActor
final class OneWayChannelTrackerTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory
    private typealias Variants = RoadRegulationVariantFactory

    /// 責務: 東へ x m を通る南北の一方通行を作ります。
    private func northOneWay(id: Int64 = 1, x: Double = 0, order: RoadRegulationOneWayOrder) -> RoadRegulation {
        Shapes.oneWay(id: id, points: [(x: x, y: -300), (x: x, y: 300)], order: order)
    }

    /// 責務: 点 (x, 0)・向き・候補から観測した状態を返します。
    private func observe(
        x: Double = 0,
        heading: Double?,
        regulations: [RoadRegulation],
        inside: Bool = true,
        current: OneWayChannelStatus = .pending,
        applicability: @escaping (RoadRegulation, Date) -> RegulationApplicability = RoadRegulationApplicabilityTable.closure([:])
    ) -> OneWayChannelStatus {
        OneWayChannelTracker().observedStatus(
            point: Points.point(x: x, y: 0, accuracy: 5),
            heading: heading,
            context: RoadRegulationCandidateContext(regulations: regulations, isInsideDataCoverage: inside),
            current: current,
            applicability: applicability
        )
    }

    /// 責務: 「判定できない」の理由を返します(それ以外の状態なら `nil`)。
    private func reason(_ status: OneWayChannelStatus) -> RoadRegulationUndeterminedReason? {
        if case .undeterminable(let reason, _) = status { return reason }
        return nil
    }

    /// 責務: 行 ID 1 の一方通行に乗った状態を返します。
    private func on(_ direction: OneWayTravelDirection, id: Int64 = 1) -> OneWayChannelStatus {
        .on(RoadRegulationID(rawValue: id), direction)
    }

    /// 責務: 並び2で北向きは `permitted`、南向きは `reverse` になることを確かめます。
    func testPermittedOrderNorthboundIsPermittedAndSouthboundIsReverse() {
        let road = northOneWay(order: .permittedDirection)
        XCTAssertEqual(observe(heading: 0, regulations: [road]), on(.permitted))
        XCTAssertEqual(observe(heading: 180, regulations: [road]), on(.reverse))
    }

    /// 責務: 並び1で南向きは `permitted`、北向きは `reverse` になることを確かめます。
    func testProhibitedOrderSouthboundIsPermittedAndNorthboundIsReverse() {
        let road = northOneWay(order: .prohibitedDirection)
        XCTAssertEqual(observe(heading: 180, regulations: [road]), on(.permitted))
        XCTAssertEqual(observe(heading: 0, regulations: [road]), on(.reverse))
    }

    /// 責務: 通行できる向きとの角度差 39 度は `permitted`、41 度は候補にせず `none` になることを確かめます。
    func testPermittedHeadingBoundary() {
        let road = northOneWay(order: .permittedDirection)
        XCTAssertEqual(observe(heading: 39, regulations: [road]), on(.permitted))
        XCTAssertEqual(observe(heading: 41, regulations: [road]), OneWayChannelStatus.none)
    }

    /// 責務: 角度差 141 度は `reverse`、139 度は候補にせず `none` になることを確かめます。
    func testReverseHeadingBoundary() {
        let road = northOneWay(order: .permittedDirection)
        XCTAssertEqual(observe(heading: 141, regulations: [road]), on(.reverse))
        XCTAssertEqual(observe(heading: 139, regulations: [road]), OneWayChannelStatus.none)
    }

    /// 責務: 横切る向き(東向き)では候補にせず `none` になることを確かめます。
    func testCrossingHeadingIsNone() {
        XCTAssertEqual(observe(heading: 90, regulations: [northOneWay(order: .permittedDirection)]), OneWayChannelStatus.none)
    }

    /// 責務: 向きが分からず許容内(16.5 m)なら ID つきの `headingUnknown`、許容外(17.5 m)なら `none` になることを確かめます。
    func testUnknownHeadingWithinToleranceIsHeadingUnknown() {
        let road = northOneWay(order: .permittedDirection)
        XCTAssertEqual(observe(x: 16.5, heading: nil, regulations: [road]), .undeterminable(.headingUnknown, RoadRegulationID(rawValue: 1)))
        XCTAssertEqual(observe(x: 17.5, heading: nil, regulations: [road]), OneWayChannelStatus.none)
    }

    /// 責務: 候補が無い時と、一方通行でない線しか無い時は `none` になることを確かめます。
    func testNoOneWayCandidateIsNone() {
        let speedLine = Shapes.line(id: 2, points: [(x: 0, y: -300), (x: 0, y: 300)])
        let slowDown = Shapes.line(id: 3, kind: .slowDown, points: [(x: 0, y: -300), (x: 0, y: 300)], speedLimitKph: nil)
        XCTAssertEqual(observe(heading: 0, regulations: []), OneWayChannelStatus.none)
        XCTAssertEqual(observe(heading: 0, regulations: [speedLine, slowDown]), OneWayChannelStatus.none)
    }

    /// 責務: 横方向の許容の内側(16.5 m)は乗り、外側(17.5 m)は `none` になることを確かめます。
    func testLateralToleranceBoundary() {
        let road = northOneWay(order: .permittedDirection)
        XCTAssertEqual(observe(x: 16.5, heading: 0, regulations: [road]), on(.permitted))
        XCTAssertEqual(observe(x: 17.5, heading: 0, regulations: [road]), OneWayChannelStatus.none)
    }

    /// 責務: いま乗っている一方通行は 27 m まで残り(26.5 m で乗る)、乗っていなければ 26.5 m で `none` になることを確かめます。
    func testCurrentOneWayStaysWithinExitHysteresis() {
        let road = northOneWay(order: .permittedDirection)
        XCTAssertEqual(observe(x: 26.5, heading: 0, regulations: [road], current: on(.permitted)), on(.permitted))
        XCTAssertEqual(observe(x: 26.5, heading: 0, regulations: [road], current: OneWayChannelStatus.none), OneWayChannelStatus.none)
        XCTAssertEqual(observe(x: 27.5, heading: 0, regulations: [road], current: on(.permitted)), OneWayChannelStatus.none)
    }

    /// 責務: 対象が自転車(対象車両 D=100)だけの一方通行は、実物の条件の評価で当てはまらず候補にしないことを確かめます。
    func testBicycleOnlyOneWayIsNotCandidate() {
        let bicycleOnly = Variants.withConditions(
            northOneWay(order: .permittedDirection),
            Variants.targetOnly(RoadRegulationConditionSet(vehicleCodeD: "100"))
        )
        let unconditional = northOneWay(order: .permittedDirection)
        let real = RoadRegulationApplicabilityTable.realEvaluator()
        XCTAssertEqual(observe(heading: 0, regulations: [bicycleOnly], applicability: real), OneWayChannelStatus.none)
        XCTAssertEqual(observe(heading: 0, regulations: [unconditional], applicability: real), on(.permitted))
    }

    /// 責務: 条件が `doesNotApply` なら `none`、`unknown` なら `conditionUnknown` になることを確かめます。
    func testConditionOfBestCandidate() {
        let road = northOneWay(order: .permittedDirection)
        XCTAssertEqual(
            observe(heading: 0, regulations: [road], applicability: RoadRegulationApplicabilityTable.closure([1: .doesNotApply])),
            OneWayChannelStatus.none
        )
        let unknown = observe(heading: 0, regulations: [road], applicability: RoadRegulationApplicabilityTable.closure([1: .unknown]))
        XCTAssertEqual(reason(unknown), .conditionUnknown)
    }

    /// 責務: 向きの逆な2本が点数差 3 m の内側(2.5 m)なら曖昧、外側(3.5 m)なら最良の道を採ることを確かめます。
    func testOppositeOneWaysWithinAmbiguityMargin() {
        let best = northOneWay(id: 1, x: -5, order: .permittedDirection)
        let closeOpposite = northOneWay(id: 2, x: 7.5, order: .prohibitedDirection)
        let farOpposite = northOneWay(id: 2, x: 8.5, order: .prohibitedDirection)
        XCTAssertEqual(reason(observe(heading: 0, regulations: [best, closeOpposite])), .ambiguousCandidates)
        XCTAssertEqual(observe(heading: 0, regulations: [best, farOpposite]), on(.permitted))
    }

    /// 責務: 粗い線分(長さ 3,000 m)の一方通行の近く(50 m)は、ID つきの `coarseGeometry` になることを確かめます。
    func testCoarseOneWayIsCoarseGeometry() {
        let coarse = Shapes.oneWay(id: 4, points: [(x: 0, y: -1_500), (x: 0, y: 1_500)], order: .permittedDirection)
        XCTAssertEqual(observe(x: 50, heading: 0, regulations: [coarse]), .undeterminable(.coarseGeometry, RoadRegulationID(rawValue: 4)))
    }

    /// 責務: 候補が無ければ、データの範囲の内でも外でも `none` になり、外でも `outsideRegulationData` にしないことを確かめます
    /// (範囲の外を `outsideRegulationData` にするのは最高速度の経路だけ)。
    func testNoCandidateIsNoneRegardlessOfDataCoverage() {
        XCTAssertEqual(observe(heading: 0, regulations: [], inside: true), OneWayChannelStatus.none)
        XCTAssertEqual(observe(heading: 0, regulations: [], inside: false), OneWayChannelStatus.none)
        let speedLimit = SpeedLimitChannelTracker().observedStatus(
            point: Points.point(x: 0, y: 0, accuracy: 5),
            heading: 0,
            context: RoadRegulationCandidateContext(regulations: [], isInsideDataCoverage: false),
            current: .pending,
            applicability: RoadRegulationApplicabilityTable.closure([:])
        )
        XCTAssertEqual(speedLimit, .undeterminable(.outsideRegulationData, nil))
    }

    /// 責務: 1位の一方通行の除外の形状が許容内(3 m)にあれば `nearExclusionArea` になることを確かめます。
    func testExclusionWithinToleranceIsNearExclusionArea() {
        let road = Variants.addingExclusion(northOneWay(order: .permittedDirection), [(x: 3, y: -20), (x: 3, y: 20)])
        XCTAssertEqual(reason(observe(heading: 0, regulations: [road])), .nearExclusionArea)
    }

    /// 責務: 向きが分からず、条件の判定が違う候補が点数差 3 m 未満で並ぶ時は、規制なしの `headingUnknown` になることを確かめます。
    func testUnknownHeadingWithConflictingCandidatesIsHeadingUnknownWithoutID() {
        let first = northOneWay(id: 1, x: -5, order: .permittedDirection)
        let second = northOneWay(id: 2, x: 6, order: .permittedDirection)
        let status = observe(
            heading: nil,
            regulations: [first, second],
            applicability: RoadRegulationApplicabilityTable.closure([2: .unknown])
        )
        XCTAssertEqual(status, .undeterminable(.headingUnknown, nil))
    }
}
