import XCTest
@testable import ProjectZD8

/// `RoadRegulationLineCandidateEvaluator` が、進む向き h と線分の方位 b の角度差で候補を絞ることを検証します(設計書 §3.5、TB2)。
///
/// - 向きを区別しない(`directionAgnostic`): min(角度差(h, b), 角度差(h, b + 180)) ≤ 40 度なら候補。
/// - 一方通行(`oneWay`): 通行できる向き p(並びが通行の向きなら b、禁止の向きなら b + 180)との角度差 ≤ 40 → `permitted`、
///   ≥ 140 → `reverse`、その間は候補にしない。向きが分からなければ候補に残し、進む向きは `nil`。
///
/// 道は南北の線 (0, −200)–(0, 200)(b = 0 度)、点は (3, 0)・精度 0 です。境界は ±1 度で確かめます。
@MainActor
final class RoadRegulationLineCandidateEvaluatorHeadingTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory

    /// 責務: 点 (x, y)・向き・方式で、1件の規制を評価します。
    private func matches(
        _ regulation: RoadRegulation,
        heading: Double?,
        mode: RoadRegulationLineCandidateEvaluator.Mode = .directionAgnostic,
        x: Double = 3,
        y: Double = 0,
        thresholds: RoadRegulationMatchingThresholds = .standard
    ) -> [RoadRegulationLineMatch] {
        RoadRegulationLineCandidateEvaluator(thresholds: thresholds).matches(
            point: Points.point(x: x, y: y, accuracy: 0),
            heading: heading,
            candidates: [regulation],
            mode: mode,
            currentRegulationID: nil
        )
    }

    /// 責務: 南北の最高速度の区間を返します。
    private func northRoad() -> RoadRegulation {
        Shapes.line(id: 1, points: [(x: 0, y: -200), (x: 0, y: 200)])
    }

    /// 責務: 南から北へ座標が並ぶ一方通行を返します。
    private func northOneWay(_ order: RoadRegulationOneWayOrder) -> RoadRegulation {
        Shapes.oneWay(id: 2, points: [(x: 0, y: -200), (x: 0, y: 200)], order: order)
    }

    /// 責務: 一方通行の方式で評価した結果の進む向きを返します(候補にならなければ空)。
    private func directions(_ order: RoadRegulationOneWayOrder, heading: Double?) -> [OneWayTravelDirection?] {
        matches(northOneWay(order), heading: heading, mode: .oneWay).map(\.travelDirection)
    }

    /// 責務: 角度差 39 度は入り(角度差 39・点数 3 + 0.2 × 39 = 10.8)、41 度は入らないことを確かめます。
    func testAlignmentBoundary() throws {
        let inside = try XCTUnwrap(matches(northRoad(), heading: 39).first)
        XCTAssertEqual(try XCTUnwrap(inside.headingDifference), 39, accuracy: 0.01)
        XCTAssertEqual(inside.score, 10.8, accuracy: 0.01)
        XCTAssertEqual(matches(northRoad(), heading: 41), [])
        XCTAssertEqual(matches(northRoad(), heading: 321).count, 1)
        XCTAssertEqual(matches(northRoad(), heading: 319), [])
    }

    /// 責務: 向きを区別しない時は逆向きも入る(180 度 → 角度差 0、219 度 → 39)、221 度は入らないことを確かめます。
    func testDirectionAgnosticAcceptsReverseTravel() throws {
        let reverse = try XCTUnwrap(matches(northRoad(), heading: 180).first)
        XCTAssertEqual(try XCTUnwrap(reverse.headingDifference), 0, accuracy: 0.01)
        XCTAssertNil(reverse.travelDirection)
        let nearReverse = try XCTUnwrap(matches(northRoad(), heading: 219).first)
        XCTAssertEqual(try XCTUnwrap(nearReverse.headingDifference), 39, accuracy: 0.01)
        XCTAssertEqual(matches(northRoad(), heading: 221), [])
    }

    /// 責務: 359 度と 0 度の線の角度差を 1 度として扱う(360 度の折り返し)ことを確かめます。
    func testHeadingDifferenceWrapsAround() throws {
        let match = try XCTUnwrap(matches(northRoad(), heading: 359).first)
        XCTAssertEqual(try XCTUnwrap(match.headingDifference), 1, accuracy: 0.01)
    }

    /// 責務: 向きが分からなければ角度で絞らず候補に残し、角度差は nil・点数は距離だけになることを確かめます。
    func testUnknownHeadingKeepsCandidate() throws {
        let match = try XCTUnwrap(matches(northRoad(), heading: nil).first)
        XCTAssertNil(match.headingDifference)
        XCTAssertEqual(match.score, 3, accuracy: 0.01)
    }

    /// 責務: 折れ線では点に最も近い線分の方位で比べることを確かめます。
    ///
    /// 線 (0, 0)–(0, 100)–(100, 100) で、点 (50, 103) に最も近いのは東向き(90 度)の2本目です。
    func testNearestSegmentBearingIsUsed() throws {
        let bend = Shapes.line(id: 3, points: [(x: 0, y: 0), (x: 0, y: 100), (x: 100, y: 100)])
        let east = try XCTUnwrap(matches(bend, heading: 90, x: 50, y: 103).first)
        XCTAssertEqual(east.distanceMeters, 3, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(east.headingDifference), 0, accuracy: 0.01)
        XCTAssertEqual(matches(bend, heading: 0, x: 50, y: 103), [])
    }

    /// 責務: 並びが通行の向き(2)の一方通行で、北向きは permitted、南向きは reverse になることを確かめます。
    func testPermittedOrderClassifiesTravelDirection() {
        XCTAssertEqual(directions(.permittedDirection, heading: 10), [.permitted])
        XCTAssertEqual(directions(.permittedDirection, heading: 190), [.reverse])
    }

    /// 責務: 一方通行の角度差は、permitted なら通行できる向きとの差 d、reverse なら 180 − d で、点数もその値で求めることを確かめます。
    ///
    /// 向き 10 度 → permitted・角度差 10・点数 3 + 2 = 5。向き 190 度 → d = 170・reverse・角度差 10・点数 5。
    func testOneWayHeadingDifferenceAndScore() throws {
        let permitted = try XCTUnwrap(matches(northOneWay(.permittedDirection), heading: 10, mode: .oneWay).first)
        let reverse = try XCTUnwrap(matches(northOneWay(.permittedDirection), heading: 190, mode: .oneWay).first)
        XCTAssertEqual(try XCTUnwrap(permitted.headingDifference), 10, accuracy: 0.01)
        XCTAssertEqual(permitted.score, 5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(reverse.headingDifference), 10, accuracy: 0.01)
        XCTAssertEqual(reverse.score, 5, accuracy: 0.01)
    }

    /// 責務: 並びが禁止の向き(1)の一方通行では通行できる向きが b + 180 になり、南向きが permitted、北向きが reverse になることを確かめます。
    func testProhibitedOrderFlipsPermittedDirection() {
        XCTAssertEqual(directions(.prohibitedDirection, heading: 190), [.permitted])
        XCTAssertEqual(directions(.prohibitedDirection, heading: 10), [.reverse])
    }

    /// 責務: 一方通行の境界を確かめます(39 度 → permitted、41 度と 139 度 → 候補にしない、141 度 → reverse)。
    func testOneWayDirectionBoundaries() {
        XCTAssertEqual(directions(.permittedDirection, heading: 39), [.permitted])
        XCTAssertEqual(directions(.permittedDirection, heading: 41), [])
        XCTAssertEqual(directions(.permittedDirection, heading: 139), [])
        XCTAssertEqual(directions(.permittedDirection, heading: 141), [.reverse])
    }

    /// 責務: 一方通行で向きが分からない時は、許容内の候補を進む向き nil で残すことを確かめます(経路側で `headingUnknown` にするため)。
    func testOneWayWithUnknownHeadingKeepsCandidateWithoutDirection() {
        XCTAssertEqual(directions(.permittedDirection, heading: nil), [nil])
    }

    /// 責務: 一方通行の方式でも、許容の外(精度 0 で 15.5 m)の候補は向きが合っても出さないことを確かめます。
    func testOneWayStillRequiresLateralTolerance() {
        XCTAssertEqual(matches(northOneWay(.permittedDirection), heading: 0, mode: .oneWay, x: 15.5), [])
    }

    /// 責務: 向きが合うとみなす角度を 20 度に下げると 30 度の候補が外れることを確かめます(埋め込みの数値でない)。
    func testAlignmentThresholdIsConfigurable() {
        var thresholds = RoadRegulationMatchingThresholds.standard
        thresholds.headingAlignmentDegrees = 20
        XCTAssertEqual(matches(northRoad(), heading: 30, thresholds: thresholds), [])
        XCTAssertEqual(matches(northRoad(), heading: 30).count, 1)
    }

    /// 責務: 逆向きとみなす角度を 160 度に上げると、一方通行で 150 度が reverse にならず候補から外れることを確かめます(埋め込みの数値でない)。
    func testReverseThresholdIsConfigurable() {
        var thresholds = RoadRegulationMatchingThresholds.standard
        thresholds.reverseHeadingDegrees = 160
        XCTAssertEqual(matches(northOneWay(.permittedDirection), heading: 150, mode: .oneWay, thresholds: thresholds), [])
        XCTAssertEqual(directions(.permittedDirection, heading: 150), [.reverse])
    }
}
