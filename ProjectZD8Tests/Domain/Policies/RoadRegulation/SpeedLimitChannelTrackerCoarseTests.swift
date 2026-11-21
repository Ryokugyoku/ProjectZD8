import XCTest
@testable import ProjectZD8

/// `SpeedLimitChannelTracker` が、粗い線分(長さ 1,000 m 超)の近くを `undeterminable(.coarseGeometry, id)` にすることを検証します
/// (設計書 §3.5 の 2 の「1,000 m 以下だけ使う」と 3、TB4)。
///
/// 粗い道は東西の1本の線分 (−1,500, 0)–(1,500, 0)(長さ 3,000 m)で、点は (0, y)・精度 5 m に置きます。
/// 粗い線分の幅は 100 m です。線分の長さの境界は 999 m と 1,001 m、幅の境界は 99.5 m と 100.5 m で確かめます。
@MainActor
final class SpeedLimitChannelTrackerCoarseTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory

    /// 粗い道の行 ID です。
    private let coarseID = RoadRegulationID(rawValue: 9)

    /// 責務: 北へ y m を通る、1本の長い線分の東西の道を作ります。
    private func coarseRoad(y: Double = 0, halfLength: Double = 1_500) -> RoadRegulation {
        Shapes.line(id: coarseID.rawValue, points: [(x: -halfLength, y: y), (x: halfLength, y: y)], speedLimitKph: 50)
    }

    /// 責務: 点 (0, y)・向き・候補から観測した状態を返します。
    private func observe(y: Double, heading: Double? = 90, regulations: [RoadRegulation]) -> SpeedLimitStatus {
        SpeedLimitChannelTracker().observedStatus(
            point: Points.point(x: 0, y: y, accuracy: 5),
            heading: heading,
            context: RoadRegulationCandidateContext(regulations: regulations, isInsideDataCoverage: true),
            current: .pending,
            applicability: RoadRegulationApplicabilityTable.closure([:])
        )
    }

    /// 責務: 粗い道から 50 m で向きが合えば、その道の ID つきで `coarseGeometry` になることを確かめます。
    func testAlignedPointNearCoarseSegmentIsCoarseGeometry() {
        XCTAssertEqual(observe(y: 50, regulations: [coarseRoad()]), .undeterminable(.coarseGeometry, coarseID))
    }

    /// 責務: 向きが分からない時も、粗い道の近くは `coarseGeometry` になることを確かめます。
    func testUnknownHeadingNearCoarseSegmentIsCoarseGeometry() {
        XCTAssertEqual(observe(y: 50, heading: nil, regulations: [coarseRoad()]), .undeterminable(.coarseGeometry, coarseID))
    }

    /// 責務: 粗い道と向きが合わない(直交する)時は、粗さで判定できないとせず `unregulated` になることを確かめます。
    func testCrossingHeadingNearCoarseSegmentIsUnregulated() {
        XCTAssertEqual(observe(y: 50, heading: 0, regulations: [coarseRoad()]), .unregulated)
    }

    /// 責務: 粗い線分の幅 100 m の内側(99.5 m)は `coarseGeometry`、外側(100.5 m)は `unregulated` になることを確かめます。
    func testCoarseCorridorBoundary() {
        XCTAssertEqual(observe(y: 99.5, regulations: [coarseRoad()]), .undeterminable(.coarseGeometry, coarseID))
        XCTAssertEqual(observe(y: 100.5, regulations: [coarseRoad()]), .unregulated)
    }

    /// 責務: 粗い線分の上(5 m)でも、許容内の線として `regulated` にしないことを確かめます(1,000 m 以下だけ使う)。
    func testCoarseSegmentIsNotUsedAsRegulatedLine() {
        XCTAssertEqual(observe(y: 5, regulations: [coarseRoad()]), .undeterminable(.coarseGeometry, coarseID))
    }

    /// 責務: 長さ 999 m の線分は通常の線(5 m で `regulated`、50 m で `unregulated`)、1,001 m は粗い線分になることを確かめます。
    func testSegmentLengthBoundary() {
        let fine = coarseRoad(halfLength: 499.5)
        let coarse = coarseRoad(halfLength: 500.5)
        XCTAssertEqual(observe(y: 5, regulations: [fine]), .regulated(coarseID, limitKph: 50))
        XCTAssertEqual(observe(y: 50, regulations: [fine]), .unregulated)
        XCTAssertEqual(observe(y: 5, regulations: [coarse]), .undeterminable(.coarseGeometry, coarseID))
        XCTAssertEqual(observe(y: 50, regulations: [coarse]), .undeterminable(.coarseGeometry, coarseID))
    }

    /// 責務: 許容内に通常の線があれば、近くの粗い線分より先に通常の線で `regulated` にすることを確かめます(2 が 3 より先)。
    func testFineLineWinsOverNearbyCoarseSegment() {
        let fine = Shapes.line(id: 1, points: [(x: -300, y: 5), (x: 300, y: 5)], speedLimitKph: 40)
        let status = observe(y: 0, regulations: [coarseRoad(y: 30), fine])
        XCTAssertEqual(status, .regulated(RoadRegulationID(rawValue: 1), limitKph: 40))
    }

    /// 責務: 粗い線分は、区域(114)の内側にあっても先に `coarseGeometry` にすることを確かめます(3 が 4 より先)。
    func testCoarseSegmentWinsOverZone() {
        let zone = Shapes.zone(id: 2, ring: [(x: -400, y: -400), (x: 400, y: -400), (x: 400, y: 400), (x: -400, y: 400)])
        XCTAssertEqual(observe(y: 50, regulations: [zone, coarseRoad()]), .undeterminable(.coarseGeometry, coarseID))
    }
}
