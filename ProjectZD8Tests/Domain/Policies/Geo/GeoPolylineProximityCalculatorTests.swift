import XCTest
@testable import ProjectZD8

/// `GeoPolylineProximityCalculator` の最近傍・線分ごとの近さ・経路長を、メートル単位で作った形状で検証します。
final class GeoPolylineProximityCalculatorTests: XCTestCase {
    private let calculator = GeoPolylineProximityCalculator()
    private let geo = GeoTestCoordinates()
    private let tolerance = 0.01

    /// 責務: 北向きの20 m の線分 (0,0)→(0,20) を返します。
    private var northSegment: [GeoCoordinate] {
        geo.points([(0, 0), (0, 20)])
    }

    /// 責務: L字の経路 (0,0)→(0,20)→(20,20)(全長40 m)を返します。
    private var lShape: [GeoCoordinate] {
        geo.points([(0, 0), (0, 20), (20, 20)])
    }

    // MARK: nearest(単一の線分)

    /// 責務: 設計書の例(線分 (0,0)–(0,20)、点 (5,10) → 距離5、t = 0.5)と、線分の諸量を確かめます。
    func testMidpointSideOffsetGivesDistanceAndHalfFraction() throws {
        let result = try XCTUnwrap(calculator.nearest(to: geo.point(x: 5, y: 10), on: northSegment))
        XCTAssertEqual(result.segmentIndex, 0)
        XCTAssertEqual(result.distanceMeters, 5, accuracy: tolerance)
        XCTAssertEqual(result.fraction, 0.5, accuracy: 1e-4)
        XCTAssertEqual(result.segmentLengthMeters, 20, accuracy: tolerance)
        XCTAssertEqual(result.alongMetersFromStart, 10, accuracy: tolerance)
        XCTAssertEqual(result.segmentBearingDegrees, 0, accuracy: 1e-3)
    }

    /// 責務: 反対側(西)の横ずれでも距離が同じ5 mであることを確かめます。
    func testOppositeSideOffsetGivesSameDistance() throws {
        let result = try XCTUnwrap(calculator.nearest(to: geo.point(x: -5, y: 10), on: northSegment))
        XCTAssertEqual(result.distanceMeters, 5, accuracy: tolerance)
        XCTAssertEqual(result.fraction, 0.5, accuracy: 1e-4)
    }

    /// 責務: 設計書の例(点 (0,25) → 終点までの距離5、t = 1)を確かめます。
    func testPointBeyondEndClampsToEndpoint() throws {
        let result = try XCTUnwrap(calculator.nearest(to: geo.point(x: 0, y: 25), on: northSegment))
        XCTAssertEqual(result.distanceMeters, 5, accuracy: tolerance)
        XCTAssertEqual(result.fraction, 1, accuracy: 1e-9)
        XCTAssertEqual(result.alongMetersFromStart, 20, accuracy: tolerance)
    }

    /// 責務: 始点の外側の点が始点までの距離で t = 0 になることを確かめます。
    func testPointBeforeStartClampsToStartpoint() throws {
        let result = try XCTUnwrap(calculator.nearest(to: geo.point(x: 0, y: -5), on: northSegment))
        XCTAssertEqual(result.distanceMeters, 5, accuracy: tolerance)
        XCTAssertEqual(result.fraction, 0, accuracy: 1e-9)
        XCTAssertEqual(result.alongMetersFromStart, 0, accuracy: tolerance)
    }

    /// 責務: 外側かつ横にずれた点(3-4-5 の三角形)が端点までの距離5になることを確かめます。
    func testPointOutsideAndBesideEndpointMeasuresToEndpoint() throws {
        let result = try XCTUnwrap(calculator.nearest(to: geo.point(x: 3, y: 24), on: northSegment))
        XCTAssertEqual(result.distanceMeters, 5, accuracy: tolerance)
        XCTAssertEqual(result.fraction, 1, accuracy: 1e-9)
    }

    /// 責務: 線分上の点の距離が 0 であることを確かめます。
    func testPointOnSegmentHasZeroDistance() throws {
        let result = try XCTUnwrap(calculator.nearest(to: geo.point(x: 0, y: 5), on: northSegment))
        XCTAssertEqual(result.distanceMeters, 0, accuracy: tolerance)
        XCTAssertEqual(result.fraction, 0.25, accuracy: 1e-4)
    }

    /// 責務: 東向き・南向きの線分で方位がそれぞれ 90・180 になることを確かめます。
    func testSegmentBearingFollowsDirectionOfTravel() throws {
        let east = geo.points([(0, 0), (20, 0)])
        let south = geo.points([(0, 20), (0, 0)])
        let probe = geo.point(x: 5, y: 5)
        XCTAssertEqual(try XCTUnwrap(calculator.nearest(to: probe, on: east)).segmentBearingDegrees, 90, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(calculator.nearest(to: probe, on: south)).segmentBearingDegrees, 180, accuracy: 1e-3)
    }

    // MARK: nearest(複数の線分・nil の条件)

    /// 責務: 後ろの線分が近い時に、その番号・近さ・始点からの道のりを返すことを確かめます。
    /// 点 (15,25) は L字の2本目 (0,20)–(20,20) へ距離5、t = 0.75、始点から 20 + 15 = 35 m。
    func testNearestChoosesSecondSegmentWithCumulativeAlongDistance() throws {
        let result = try XCTUnwrap(calculator.nearest(to: geo.point(x: 15, y: 25), on: lShape))
        XCTAssertEqual(result.segmentIndex, 1)
        XCTAssertEqual(result.distanceMeters, 5, accuracy: tolerance)
        XCTAssertEqual(result.fraction, 0.75, accuracy: 1e-4)
        XCTAssertEqual(result.alongMetersFromStart, 35, accuracy: tolerance)
        XCTAssertEqual(result.segmentBearingDegrees, 90, accuracy: 1e-3)
        XCTAssertEqual(result.segmentLengthMeters, 20, accuracy: tolerance)
    }

    /// 責務: 前の線分が近い時に最初の線分を選ぶことを確かめます。
    func testNearestChoosesFirstSegmentWhenCloser() throws {
        let result = try XCTUnwrap(calculator.nearest(to: geo.point(x: -3, y: 10), on: lShape))
        XCTAssertEqual(result.segmentIndex, 0)
        XCTAssertEqual(result.distanceMeters, 3, accuracy: tolerance)
    }

    /// 責務: 点が0個・1個の折れ線では `nil` になることを確かめます。
    func testNearestReturnsNilForFewerThanTwoPoints() {
        XCTAssertNil(calculator.nearest(to: geo.point(x: 1, y: 1), on: []))
        XCTAssertNil(calculator.nearest(to: geo.point(x: 1, y: 1), on: [geo.point(x: 0, y: 0)]))
    }

    /// 責務: 長さ0の線分だけ(全点が同じ)の折れ線では `nil` になることを確かめます。
    func testNearestReturnsNilWhenAllSegmentsHaveZeroLength() {
        let same = geo.point(x: 0, y: 0)
        XCTAssertNil(calculator.nearest(to: geo.point(x: 1, y: 1), on: [same, same, same]))
    }

    /// 責務: 長さ0の線分が混じっていても、長さのある線分から結果を返すことを確かめます。
    func testNearestSkipsZeroLengthSegmentAmongRealOnes() throws {
        let polyline = geo.points([(0, 0), (0, 0), (0, 20)])
        let result = try XCTUnwrap(calculator.nearest(to: geo.point(x: 5, y: 10), on: polyline))
        XCTAssertEqual(result.segmentIndex, 1)
        XCTAssertEqual(result.distanceMeters, 5, accuracy: tolerance)
        XCTAssertEqual(result.alongMetersFromStart, 10, accuracy: tolerance)
    }

    // MARK: nearestSegments

    /// 責務: 線分ごとに1件、番号の昇順で、各線分への距離と t が返ることを確かめます。
    /// 点 (5,10) は1本目へ距離5・t=0.5、2本目 (0,20)–(20,20) へ最近点 (5,20) で距離10・t=0.25。
    func testNearestSegmentsReturnsOneEntryPerSegment() {
        let results = calculator.nearestSegments(to: geo.point(x: 5, y: 10), on: lShape)
        XCTAssertEqual(results.map(\.segmentIndex), [0, 1])
        XCTAssertEqual(results[0].distanceMeters, 5, accuracy: tolerance)
        XCTAssertEqual(results[0].fraction, 0.5, accuracy: 1e-4)
        XCTAssertEqual(results[1].distanceMeters, 10, accuracy: tolerance)
        XCTAssertEqual(results[1].fraction, 0.25, accuracy: 1e-4)
        XCTAssertEqual(results[1].alongMetersFromStart, 25, accuracy: tolerance)
    }

    /// 責務: 点が2個未満の折れ線では空配列が返ることを確かめます。
    func testNearestSegmentsIsEmptyForFewerThanTwoPoints() {
        XCTAssertTrue(calculator.nearestSegments(to: geo.point(x: 1, y: 1), on: []).isEmpty)
        XCTAssertTrue(calculator.nearestSegments(to: geo.point(x: 1, y: 1), on: [geo.point(x: 0, y: 0)]).isEmpty)
    }

    // MARK: pathLengthMeters

    /// 責務: L字の経路長が 20 + 20 = 40 m であることを確かめます。
    func testPathLengthSumsSegmentLengths() {
        XCTAssertEqual(calculator.pathLengthMeters(lShape), 40, accuracy: tolerance)
    }

    /// 責務: 点が0個・1個の経路長が 0 であることを確かめます。
    func testPathLengthIsZeroForFewerThanTwoPoints() {
        XCTAssertEqual(calculator.pathLengthMeters([]), 0)
        XCTAssertEqual(calculator.pathLengthMeters([geo.point(x: 3, y: 4)]), 0)
    }

    /// 責務: 戻りを含む経路(往復)では長さが往復の合計になることを確かめます(0→30→0 で 60 m)。
    func testPathLengthCountsBacktracking() {
        let path = geo.points([(0, 0), (30, 0), (0, 0)])
        XCTAssertEqual(calculator.pathLengthMeters(path), 60, accuracy: tolerance)
    }
}
