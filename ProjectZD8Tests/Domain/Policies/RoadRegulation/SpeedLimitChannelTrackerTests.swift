import XCTest
@testable import ProjectZD8

/// `SpeedLimitChannelTracker` が、最高速度の区間(112)と可変区間(113)の線の候補から観測した状態を決めることを検証します
/// (設計書 §3.5「最高速度の経路で観測した状態」の 1・2・5、TB4)。
///
/// 道は東西の線 (−300, y)–(300, y)(方位 90 度・長さ 600 m)で、点は (x, 0)・精度 5 m に置きます。
/// 横方向の許容は clamp(12 + 5, 15, 35) = 17 m、いま乗っている候補は 27 m です。
/// 点数 = 距離 + 0.2 × 角度差 − (いま乗っている候補なら 5)、曖昧さの幅は 3 m です。境界は ±0.5 m・±1 度で確かめます。
@MainActor
final class SpeedLimitChannelTrackerTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory
    private typealias Variants = RoadRegulationVariantFactory

    /// 責務: 北へ y m を通る東西の道(最高速度の区間)を作ります。
    private func eastRoad(id: Int64, y: Double = 0, limit: Int = 40) -> RoadRegulation {
        Shapes.line(id: id, points: [(x: -300, y: y), (x: 300, y: y)], speedLimitKph: limit)
    }

    /// 責務: 点 (x, y)・向き・候補から観測した状態を返します。
    private func observe(
        x: Double = 0,
        y: Double = 0,
        heading: Double? = 90,
        regulations: [RoadRegulation],
        inside: Bool = true,
        current: SpeedLimitStatus = .pending,
        applicability: [Int64: RegulationApplicability] = [:]
    ) -> SpeedLimitStatus {
        SpeedLimitChannelTracker().observedStatus(
            point: Points.point(x: x, y: y, accuracy: 5),
            heading: heading,
            context: RoadRegulationCandidateContext(regulations: regulations, isInsideDataCoverage: inside),
            current: current,
            applicability: RoadRegulationApplicabilityTable.closure(applicability)
        )
    }

    /// 責務: 「判定できない」の理由を返します(それ以外の状態なら `nil`)。
    private func reason(_ status: SpeedLimitStatus) -> RoadRegulationUndeterminedReason? {
        if case .undeterminable(let reason, _) = status { return reason }
        return nil
    }

    /// 責務: 版の範囲の外の点は、近くに道があっても `undeterminable(.outsideRegulationData, nil)` になることを確かめます(§3.5 の 1)。
    func testPointOutsideDataCoverageIsOutsideRegulationData() {
        let status = observe(regulations: [eastRoad(id: 1)], inside: false)
        XCTAssertEqual(status, .undeterminable(.outsideRegulationData, nil))
    }

    /// 責務: 候補が無い時は `unregulated`(指定なし)になることを確かめます(§3.5 の 5)。
    func testNoCandidatesIsUnregulated() {
        XCTAssertEqual(observe(regulations: []), .unregulated)
    }

    /// 責務: 向きの合う道が1本だけ許容内にあれば、その道と制限値の `regulated` になることを確かめます。
    func testSingleRoadWithinToleranceIsRegulated() {
        XCTAssertEqual(observe(y: 5, regulations: [eastRoad(id: 1, limit: 40)]), .regulated(RoadRegulationID(rawValue: 1), limitKph: 40))
    }

    /// 責務: 横方向の許容 17 m の内側(16.5 m)は乗り、外側(17.5 m)は `unregulated` になることを確かめます。
    func testLateralToleranceBoundary() {
        let road = eastRoad(id: 1)
        XCTAssertEqual(observe(y: 16.5, regulations: [road]), .regulated(RoadRegulationID(rawValue: 1), limitKph: 40))
        XCTAssertEqual(observe(y: 17.5, regulations: [road]), .unregulated)
    }

    /// 責務: いま乗っている道は +10 m(27 m)まで残り、それを超えると外れることを確かめます。
    func testCurrentRoadStaysWithinExitHysteresis() {
        let road = eastRoad(id: 1)
        let current = SpeedLimitStatus.regulated(RoadRegulationID(rawValue: 1), limitKph: 40)
        XCTAssertEqual(observe(y: 26.5, regulations: [road], current: current), current)
        XCTAssertEqual(observe(y: 26.5, regulations: [road], current: .unregulated), .unregulated)
        XCTAssertEqual(observe(y: 27.5, regulations: [road], current: current), .unregulated)
    }

    /// 責務: いまの状態が規制の分かっている `undeterminable` でも、その規制を「いま乗っている候補」として 27 m まで残すことを確かめます。
    func testUndeterminableCurrentRegulationAlsoGetsHysteresis() {
        let oneSided = RoadRegulationVariantFactory.withSide(eastRoad(id: 1), .oneSide)
        let current = SpeedLimitStatus.undeterminable(.oneSidedSection, RoadRegulationID(rawValue: 1))
        XCTAssertEqual(reason(observe(y: 26.5, regulations: [oneSided], current: current)), .oneSidedSection)
        XCTAssertEqual(observe(y: 26.5, regulations: [oneSided], current: .unregulated), .unregulated)
    }

    /// 責務: 条件が `doesNotApply` の道は候補にせず、より遠い当てはまる道を選ぶことを確かめます。
    func testCandidateWhoseConditionDoesNotApplyIsIgnored() {
        let near = eastRoad(id: 1, y: 2, limit: 30)
        let far = eastRoad(id: 2, y: -10, limit: 50)
        XCTAssertEqual(observe(regulations: [near], applicability: [1: .doesNotApply]), .unregulated)
        XCTAssertEqual(
            observe(regulations: [near, far], applicability: [1: .doesNotApply]),
            .regulated(RoadRegulationID(rawValue: 2), limitKph: 50)
        )
    }

    /// 責務: 制限の違う平行な2本の真ん中(各 6 m)は `ambiguousCandidates` になることを確かめます(TB4)。
    func testMiddleOfParallelRoadsWithDifferentLimitsIsAmbiguous() {
        let status = observe(regulations: [eastRoad(id: 1, y: -6, limit: 40), eastRoad(id: 2, y: 6, limit: 60)])
        XCTAssertEqual(reason(status), .ambiguousCandidates)
    }

    /// 責務: 点数差が 3 m の少し内側(2.5 m)は曖昧、少し外側(3.5 m)は最良の道を採ることを確かめます。
    func testAmbiguityMarginBoundary() {
        let best = eastRoad(id: 1, y: -5, limit: 40)
        XCTAssertEqual(reason(observe(regulations: [best, eastRoad(id: 2, y: 7.5, limit: 50)])), .ambiguousCandidates)
        XCTAssertEqual(
            observe(regulations: [best, eastRoad(id: 2, y: 8.5, limit: 50)]),
            .regulated(RoadRegulationID(rawValue: 1), limitKph: 40)
        )
    }

    /// 責務: 点数差が 3 m 未満でも、制限値・種別・条件の判定が同じなら曖昧にせず、点数の良い方を採ることを確かめます。
    func testCloseRoadsWithSameResultAreNotAmbiguous() {
        let status = observe(regulations: [eastRoad(id: 1, y: -5, limit: 40), eastRoad(id: 2, y: 6, limit: 40)])
        XCTAssertEqual(status, .regulated(RoadRegulationID(rawValue: 1), limitKph: 40))
    }

    /// 責務: 制限値が同じでも、条件の判定が違えば点数差 3 m 未満で曖昧になることを確かめます。
    func testCloseRoadsDifferingInApplicabilityAreAmbiguous() {
        let roads = [eastRoad(id: 1, y: -5, limit: 40), eastRoad(id: 2, y: 6, limit: 40)]
        XCTAssertEqual(reason(observe(regulations: roads, applicability: [2: .unknown])), .ambiguousCandidates)
    }

    /// 責務: 区間(112)と可変区間(113)が点数差 3 m 未満で並ぶと、種別の違いで曖昧になることを確かめます。
    func testCloseRoadsDifferingInKindAreAmbiguous() {
        let variable = Shapes.line(id: 2, kind: .speedLimitVariableSection, points: [(x: -300, y: 6), (x: 300, y: 6)], speedLimitKph: nil)
        XCTAssertEqual(reason(observe(regulations: [eastRoad(id: 1, y: -5), variable])), .ambiguousCandidates)
    }

    /// 責務: 交差点の上で、交差する道を向きで除くことを確かめます(東向きなら東西、北向きなら南北、向き不明なら曖昧)。
    func testCrossingRoadIsExcludedByHeading() {
        let eastWest = eastRoad(id: 1, limit: 40)
        let northSouth = Shapes.line(id: 2, points: [(x: 0, y: -300), (x: 0, y: 300)], speedLimitKph: 60)
        XCTAssertEqual(observe(heading: 90, regulations: [eastWest, northSouth]), .regulated(RoadRegulationID(rawValue: 1), limitKph: 40))
        XCTAssertEqual(observe(heading: 0, regulations: [eastWest, northSouth]), .regulated(RoadRegulationID(rawValue: 2), limitKph: 60))
        XCTAssertEqual(reason(observe(heading: nil, regulations: [eastWest, northSouth])), .ambiguousCandidates)
    }

    /// 責務: 角度差 39 度は乗り 41 度は乗らないこと、逆向き(270 度)も乗ることを確かめます(向きを区別しない)。
    func testHeadingAlignmentBoundaryAndReverseTravel() {
        let road = eastRoad(id: 1)
        let regulated = SpeedLimitStatus.regulated(RoadRegulationID(rawValue: 1), limitKph: 40)
        XCTAssertEqual(observe(heading: 129, regulations: [road]), regulated)
        XCTAssertEqual(observe(heading: 131, regulations: [road]), .unregulated)
        XCTAssertEqual(observe(heading: 270, regulations: [road]), regulated)
    }

    /// 責務: 一方通行・徐行・一時停止は最高速度の候補にしないことを確かめます。
    func testOtherKindsAreNotSpeedLimitCandidates() {
        let oneWay = Shapes.oneWay(id: 1, points: [(x: -300, y: 0), (x: 300, y: 0)], order: .permittedDirection)
        let slowDown = Shapes.line(id: 2, kind: .slowDown, points: [(x: -300, y: 0), (x: 300, y: 0)], speedLimitKph: nil)
        let stop = Shapes.stop(id: 3, at: (x: 10, y: 0), approaches: [(x: -5, y: 0)])
        XCTAssertEqual(observe(regulations: [oneWay, slowDown, stop]), .unregulated)
    }
}
