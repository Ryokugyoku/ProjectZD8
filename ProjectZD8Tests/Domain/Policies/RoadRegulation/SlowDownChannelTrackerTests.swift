import XCTest
@testable import ProjectZD8

/// `SlowDownChannelTracker` が、徐行(61)の線の候補を向きの区別なく(最高速度の線と同じ判定で)観測することを検証します
/// (設計書 §3.5「徐行の経路」、TB5)。
///
/// 道は南北の線 (0, −300)–(0, 300) で、点は (x, 0)・精度 5 m に置きます(許容 17 m、いま乗っている候補は 27 m、曖昧さの幅 3 m)。
@MainActor
final class SlowDownChannelTrackerTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory

    /// 責務: 東へ x m を通る南北の徐行の区間を作ります。
    private func northSlowDown(id: Int64 = 1, x: Double = 0) -> RoadRegulation {
        Shapes.line(id: id, kind: .slowDown, points: [(x: x, y: -300), (x: x, y: 300)], speedLimitKph: nil)
    }

    /// 責務: 点 (x, 0)・向き・候補から観測した状態を返します。
    private func observe(
        x: Double = 0,
        heading: Double? = 0,
        regulations: [RoadRegulation],
        inside: Bool = true,
        current: SlowDownChannelStatus = .pending,
        applicability: [Int64: RegulationApplicability] = [:]
    ) -> SlowDownChannelStatus {
        SlowDownChannelTracker().observedStatus(
            point: Points.point(x: x, y: 0, accuracy: 5),
            heading: heading,
            context: RoadRegulationCandidateContext(regulations: regulations, isInsideDataCoverage: inside),
            current: current,
            applicability: RoadRegulationApplicabilityTable.closure(applicability)
        )
    }

    /// 責務: 「判定できない」の理由を返します(それ以外の状態なら `nil`)。
    private func reason(_ status: SlowDownChannelStatus) -> RoadRegulationUndeterminedReason? {
        if case .undeterminable(let reason, _) = status { return reason }
        return nil
    }

    /// 責務: 行 ID の徐行に乗った状態を返します。
    private func on(_ id: Int64 = 1) -> SlowDownChannelStatus {
        .on(RoadRegulationID(rawValue: id))
    }

    /// 責務: 北向きでも南向きでも同じ `on(id)` になることを確かめます(向きを区別しない)。
    func testBothDirectionsAreOn() {
        XCTAssertEqual(observe(heading: 0, regulations: [northSlowDown()]), on())
        XCTAssertEqual(observe(heading: 180, regulations: [northSlowDown()]), on())
    }

    /// 責務: 向きが分からない時は向きで除かず `on(id)` になることを確かめます(最高速度の線と同じ判定)。
    func testUnknownHeadingIsNotFiltered() {
        XCTAssertEqual(observe(heading: nil, regulations: [northSlowDown()]), on())
    }

    /// 責務: 角度差 39 度は乗り、41 度と横切る向きは `none` になることを確かめます。
    func testHeadingAlignmentBoundary() {
        XCTAssertEqual(observe(heading: 219, regulations: [northSlowDown()]), on())
        XCTAssertEqual(observe(heading: 41, regulations: [northSlowDown()]), SlowDownChannelStatus.none)
        XCTAssertEqual(observe(heading: 90, regulations: [northSlowDown()]), SlowDownChannelStatus.none)
    }

    /// 責務: 横方向の許容の内側(16.5 m)は乗り、外側(17.5 m)と候補が無い時は `none` になることを確かめます。
    func testLateralToleranceBoundaryAndNoCandidate() {
        XCTAssertEqual(observe(x: 16.5, regulations: [northSlowDown()]), on())
        XCTAssertEqual(observe(x: 17.5, regulations: [northSlowDown()]), SlowDownChannelStatus.none)
        XCTAssertEqual(observe(regulations: []), SlowDownChannelStatus.none)
    }

    /// 責務: いま乗っている徐行の区間は 27 m まで残ることを確かめます(26.5 m で乗り、27.5 m で外れる)。
    func testCurrentSlowDownStaysWithinExitHysteresis() {
        XCTAssertEqual(observe(x: 26.5, regulations: [northSlowDown()], current: on()), on())
        XCTAssertEqual(observe(x: 26.5, regulations: [northSlowDown()], current: SlowDownChannelStatus.none), SlowDownChannelStatus.none)
        XCTAssertEqual(observe(x: 27.5, regulations: [northSlowDown()], current: on()), SlowDownChannelStatus.none)
    }

    /// 責務: 徐行でない線(最高速度・一方通行)は候補にせず、徐行の区間があればそちらに乗ることを確かめます。
    func testOnlySlowDownLinesAreCandidates() {
        let speedLine = Shapes.line(id: 2, points: [(x: 0, y: -300), (x: 0, y: 300)])
        let oneWay = Shapes.oneWay(id: 3, points: [(x: 0, y: -300), (x: 0, y: 300)], order: .permittedDirection)
        XCTAssertEqual(observe(regulations: [speedLine, oneWay]), SlowDownChannelStatus.none)
        XCTAssertEqual(observe(regulations: [speedLine, oneWay, northSlowDown(id: 4, x: 10)]), on(4))
    }

    /// 責務: 条件が `doesNotApply` なら `none`、`unknown` なら `conditionUnknown` になることを確かめます。
    func testConditionOfBestCandidate() {
        XCTAssertEqual(observe(regulations: [northSlowDown()], applicability: [1: .doesNotApply]), SlowDownChannelStatus.none)
        XCTAssertEqual(reason(observe(regulations: [northSlowDown()], applicability: [1: .unknown])), .conditionUnknown)
    }

    /// 責務: 条件の判定の違う2本が点数差 3 m の内側(2.5 m)なら曖昧、外側(3.5 m)なら最良の道を採ることを確かめます。
    func testAmbiguityMarginBoundary() {
        let best = northSlowDown(id: 1, x: -5)
        XCTAssertEqual(
            reason(observe(regulations: [best, northSlowDown(id: 2, x: 7.5)], applicability: [2: .unknown])),
            .ambiguousCandidates
        )
        XCTAssertEqual(observe(regulations: [best, northSlowDown(id: 2, x: 8.5)], applicability: [2: .unknown]), on(1))
    }

    /// 責務: 粗い線分(長さ 3,000 m)の徐行の近く(50 m)は、ID つきの `coarseGeometry` になることを確かめます。
    func testCoarseSlowDownIsCoarseGeometry() {
        let coarse = Shapes.line(id: 6, kind: .slowDown, points: [(x: 0, y: -1_500), (x: 0, y: 1_500)], speedLimitKph: nil)
        XCTAssertEqual(observe(x: 50, regulations: [coarse]), .undeterminable(.coarseGeometry, RoadRegulationID(rawValue: 6)))
    }

    /// 責務: 候補が無ければ、データの範囲の内でも外でも `none` になり、外でも `outsideRegulationData` にしないことを確かめます
    /// (範囲の外を `outsideRegulationData` にするのは最高速度の経路だけ)。
    func testNoCandidateIsNoneRegardlessOfDataCoverage() {
        XCTAssertEqual(observe(regulations: [], inside: true), SlowDownChannelStatus.none)
        XCTAssertEqual(observe(regulations: [], inside: false), SlowDownChannelStatus.none)
        let speedLimit = SpeedLimitChannelTracker().observedStatus(
            point: Points.point(x: 0, y: 0, accuracy: 5),
            heading: 0,
            context: RoadRegulationCandidateContext(regulations: [], isInsideDataCoverage: false),
            current: .pending,
            applicability: RoadRegulationApplicabilityTable.closure([:])
        )
        XCTAssertEqual(speedLimit, .undeterminable(.outsideRegulationData, nil))
    }

    /// 責務: 1位の徐行の除外の形状が許容内(3 m)にあれば `nearExclusionArea` になることを確かめます。
    func testExclusionWithinToleranceIsNearExclusionArea() {
        let road = RoadRegulationVariantFactory.addingExclusion(northSlowDown(), [(x: 3, y: -20), (x: 3, y: 20)])
        XCTAssertEqual(reason(observe(regulations: [road])), .nearExclusionArea)
    }
}
