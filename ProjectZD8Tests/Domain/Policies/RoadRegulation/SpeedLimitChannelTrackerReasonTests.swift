import XCTest
@testable import ProjectZD8

/// `SpeedLimitChannelTracker` が、1位の線の候補を「判定できない」にする理由と、その調べる順
/// (あいまい → 可変区間 → 条件の不明 → 片側 → 除外の近く → `regulated`)を検証します(設計書 §3.5 の 2、TB4)。
///
/// 道は東西の線 (−300, 0)–(300, 0) で、点は (x, 0)・精度 5 m・東向きに置きます(許容 17 m)。
@MainActor
final class SpeedLimitChannelTrackerReasonTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory
    private typealias Variants = RoadRegulationVariantFactory

    /// 責務: 東西の道(最高速度の区間)を作ります。
    private func eastRoad(id: Int64 = 1, y: Double = 0, limit: Int? = 40) -> RoadRegulation {
        Shapes.line(id: id, points: [(x: -300, y: y), (x: 300, y: y)], speedLimitKph: limit)
    }

    /// 責務: 東西の可変区間(113)を作ります。
    private func variableRoad(id: Int64 = 3) -> RoadRegulation {
        Shapes.line(id: id, kind: .speedLimitVariableSection, points: [(x: -300, y: 0), (x: 300, y: 0)], speedLimitKph: nil)
    }

    /// 責務: 点 (x, 0)・候補から観測した状態を返します。
    private func observe(
        x: Double = 0,
        regulations: [RoadRegulation],
        applicability: [Int64: RegulationApplicability] = [:]
    ) -> SpeedLimitStatus {
        SpeedLimitChannelTracker().observedStatus(
            point: Points.point(x: x, y: 0, accuracy: 5),
            heading: 90,
            context: RoadRegulationCandidateContext(regulations: regulations, isInsideDataCoverage: true),
            current: .pending,
            applicability: RoadRegulationApplicabilityTable.closure(applicability)
        )
    }

    /// 責務: 「判定できない」の理由を返します(それ以外の状態なら `nil`)。
    private func reason(_ status: SpeedLimitStatus) -> RoadRegulationUndeterminedReason? {
        if case .undeterminable(let reason, _) = status { return reason }
        return nil
    }

    /// 責務: 1位が可変区間(113)なら `variableSpeedLimit`、条件が不明でも可変区間の判定が先に立つことを確かめます。
    func testBestVariableSectionIsVariableSpeedLimit() {
        XCTAssertEqual(reason(observe(regulations: [variableRoad()])), .variableSpeedLimit)
        XCTAssertEqual(reason(observe(regulations: [variableRoad()], applicability: [3: .unknown])), .variableSpeedLimit)
    }

    /// 責務: 制限値の無い区間(112)も `variableSpeedLimit` になることを確かめます。
    func testSectionWithoutLimitIsVariableSpeedLimit() {
        XCTAssertEqual(reason(observe(regulations: [eastRoad(limit: nil)])), .variableSpeedLimit)
    }

    /// 責務: あいまいさが可変区間より先に立つことを確かめます(1位が可変区間で、2位が点数差 3 m 未満の区間)。
    func testAmbiguityComesBeforeVariableSection() {
        let regulations = [variableRoad(), eastRoad(id: 1, y: 2)]
        XCTAssertEqual(observe(regulations: regulations), .undeterminable(.ambiguousCandidates, nil))
    }

    /// 責務: 1位の条件が `unknown` なら `conditionUnknown` になり、片側より先に立つことを確かめます。
    func testUnknownConditionComesBeforeOneSidedSection() {
        let oneSided = Variants.withSide(eastRoad(), .oneSide)
        XCTAssertEqual(reason(observe(regulations: [eastRoad()], applicability: [1: .unknown])), .conditionUnknown)
        XCTAssertEqual(reason(observe(regulations: [oneSided], applicability: [1: .unknown])), .conditionUnknown)
    }

    /// 責務: 片側・両側コードが 2(片側)なら `oneSidedSection`、1・3 なら `regulated` になることを確かめます。
    func testOneSidedSectionIsUndeterminable() {
        let regulated = SpeedLimitStatus.regulated(RoadRegulationID(rawValue: 1), limitKph: 40)
        XCTAssertEqual(reason(observe(regulations: [Variants.withSide(eastRoad(), .oneSide)])), .oneSidedSection)
        XCTAssertEqual(observe(regulations: [Variants.withSide(eastRoad(), .bothSides)]), regulated)
        XCTAssertEqual(observe(regulations: [Variants.withSide(eastRoad(), RoadRegulationSideCode.none)]), regulated)
    }

    /// 責務: 片側の判定が除外の近くより先に立つことを確かめます。
    func testOneSidedComesBeforeNearExclusion() {
        let both = Variants.addingExclusion(Variants.withSide(eastRoad(), .oneSide), [(x: -20, y: 3), (x: 20, y: 3)])
        XCTAssertEqual(reason(observe(regulations: [both])), .oneSidedSection)
    }

    /// 責務: 1位の除外の形状が許容内(3 m)にあれば `nearExclusionArea`、遠ければ(100 m 以上)`regulated` になることを確かめます。
    func testExclusionWithinToleranceIsNearExclusionArea() {
        let near = Variants.addingExclusion(eastRoad(), [(x: -20, y: 3), (x: 20, y: 3)])
        let far = Variants.addingExclusion(eastRoad(), [(x: 200, y: 0), (x: 250, y: 0)])
        XCTAssertEqual(reason(observe(x: 0, regulations: [near])), .nearExclusionArea)
        XCTAssertEqual(observe(x: -100, regulations: [far]), .regulated(RoadRegulationID(rawValue: 1), limitKph: 40))
    }
}
