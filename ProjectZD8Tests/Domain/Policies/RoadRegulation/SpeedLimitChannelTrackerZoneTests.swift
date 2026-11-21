import XCTest
@testable import ProjectZD8

/// `SpeedLimitChannelTracker` が、最高速度の区域(114。ゾーン30)の内側・外側・境界の近くを観測することを検証します
/// (設計書 §3.5 の 4、TB4)。
///
/// 区域は (−200, −200)–(200, 200) の正方形(制限 30 km/h)で、点は (x, 0)・精度 5 m に置きます。
/// 境界の近さの幅は 20 m です。境界は 19 m と 21 m(内側・外側とも)で確かめます。
@MainActor
final class SpeedLimitChannelTrackerZoneTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory
    private typealias Variants = RoadRegulationVariantFactory

    /// 区域の行 ID です。
    private let zoneID = RoadRegulationID(rawValue: 5)

    /// 責務: 一辺 2 × half m の正方形の区域を作ります。
    private func zone(id: Int64 = 5, half: Double = 200) -> RoadRegulation {
        Shapes.zone(id: id, ring: [(x: -half, y: -half), (x: half, y: -half), (x: half, y: half), (x: -half, y: half)])
    }

    /// 責務: 点 (x, 0)・候補から観測した状態を返します。
    private func observe(
        x: Double,
        heading: Double? = 90,
        regulations: [RoadRegulation],
        applicability: [Int64: RegulationApplicability] = [:]
    ) -> SpeedLimitStatus {
        SpeedLimitChannelTracker().observedStatus(
            point: Points.point(x: x, y: 0, accuracy: 5),
            heading: heading,
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

    /// 責務: 区域の奥(境界まで 200 m)は、区域の ID と制限 30 の `regulated` になることを確かめます。
    func testDeepInsideZoneIsRegulated() {
        XCTAssertEqual(observe(x: 0, regulations: [zone()]), .regulated(zoneID, limitKph: 30))
    }

    /// 責務: 内側で境界まで 19 m は `nearZoneBoundary`、21 m は `regulated` になることを確かめます。
    func testInsideBoundaryMargin() {
        XCTAssertEqual(reason(observe(x: 181, regulations: [zone()])), .nearZoneBoundary)
        XCTAssertEqual(observe(x: 179, regulations: [zone()]), .regulated(zoneID, limitKph: 30))
    }

    /// 責務: 外側で境界まで 19 m は `nearZoneBoundary`、21 m は `unregulated` になることを確かめます。
    func testOutsideBoundaryMargin() {
        XCTAssertEqual(reason(observe(x: 219, regulations: [zone()])), .nearZoneBoundary)
        XCTAssertEqual(observe(x: 221, regulations: [zone()]), .unregulated)
    }

    /// 責務: 区域の内側の判定は向きに依らないことを確かめます(向き不明・北向きでも `regulated`)。
    func testZoneIgnoresHeading() {
        XCTAssertEqual(observe(x: 0, heading: nil, regulations: [zone()]), .regulated(zoneID, limitKph: 30))
        XCTAssertEqual(observe(x: 0, heading: 0, regulations: [zone()]), .regulated(zoneID, limitKph: 30))
    }

    /// 責務: 区域の奥で条件が `unknown` なら `conditionUnknown` になることを確かめます。
    func testZoneWithUnknownConditionIsConditionUnknown() {
        XCTAssertEqual(reason(observe(x: 0, regulations: [zone()], applicability: [5: .unknown])), .conditionUnknown)
    }

    /// 責務: 条件が `doesNotApply` の区域は候補にせず、内側でも境界の近くでも `unregulated` になることを確かめます。
    func testZoneWhoseConditionDoesNotApplyIsIgnored() {
        XCTAssertEqual(observe(x: 0, regulations: [zone()], applicability: [5: .doesNotApply]), .unregulated)
        XCTAssertEqual(observe(x: 181, regulations: [zone()], applicability: [5: .doesNotApply]), .unregulated)
    }

    /// 責務: 区域の奥でも、点が除外の区域の内側にあれば `nearExclusionArea` になることを確かめます。
    func testPointInsideZoneExclusionIsNearExclusionArea() {
        let excluded = Variants.addingExclusion(
            zone(),
            [(x: -50, y: -50), (x: 50, y: -50), (x: 50, y: 50), (x: -50, y: 50), (x: -50, y: -50)]
        )
        XCTAssertEqual(reason(observe(x: 0, regulations: [excluded])), .nearExclusionArea)
    }

    /// 責務: 制限値の違う区域が重なる奥は `ambiguousCandidates` になることを確かめます。
    func testOverlappingZonesWithDifferentLimitsAreAmbiguous() {
        let other = Variants.withSpeedLimit(zone(id: 6, half: 300), 40)
        XCTAssertEqual(reason(observe(x: 0, regulations: [zone(), other])), .ambiguousCandidates)
    }

    /// 責務: 制限値の同じ区域が重なる奥は、条件が当てはまる区域のうち ID の最小のものの `regulated` になることを確かめます。
    func testOverlappingZonesWithSameLimitChooseSmallestID() {
        let other = zone(id: 6, half: 300)
        XCTAssertEqual(observe(x: 0, regulations: [other, zone()]), .regulated(zoneID, limitKph: 30))
    }

    /// 責務: 制限値の無い区域は、奥でも `variableSpeedLimit` になることを確かめます。
    func testZoneWithoutLimitIsVariableSpeedLimit() {
        XCTAssertEqual(reason(observe(x: 0, regulations: [Variants.withSpeedLimit(zone(), nil)])), .variableSpeedLimit)
    }

    /// 責務: 区域の中を通る区間(112)の上では、区間が勝つことを確かめます(TB4「区間 + 区域」)。
    func testSectionInsideZoneWins() {
        let section = Shapes.line(id: 1, points: [(x: -150, y: 0), (x: 150, y: 0)], speedLimitKph: 40)
        XCTAssertEqual(observe(x: 0, regulations: [zone(), section]), .regulated(RoadRegulationID(rawValue: 1), limitKph: 40))
    }

    /// 責務: 区域の奥でも、版の範囲の外なら `outsideRegulationData` になることを確かめます(1 が 4 より先)。
    func testOutsideDataCoverageWinsOverZone() {
        let status = SpeedLimitChannelTracker().observedStatus(
            point: Points.point(x: 0, y: 0, accuracy: 5),
            heading: 90,
            context: RoadRegulationCandidateContext(regulations: [zone()], isInsideDataCoverage: false),
            current: .pending,
            applicability: RoadRegulationApplicabilityTable.closure([:])
        )
        XCTAssertEqual(status, .undeterminable(.outsideRegulationData, nil))
    }
}
