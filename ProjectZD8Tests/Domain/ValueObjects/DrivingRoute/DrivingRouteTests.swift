import XCTest
@testable import ProjectZD8

/// `DrivingRoute` の `isEmpty`・`points`・`firstPoint`・`lastPoint` を検証します。
@MainActor
final class DrivingRouteTests: XCTestCase {
    private typealias Fixtures = DrivingRoutePointFixtures

    /// 責務: 区間を渡して、全点数と除外数 0 のルートを作ります。
    private func route(_ segments: [DrivingRouteSegment]) -> DrivingRoute {
        Fixtures.route(segments)
    }

    /// 責務: 区間が無いルートが空で、点の列も最初・最後の点も無いことを確かめます。
    func testEmptyRoute() {
        let empty = route([])
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.points, [])
        XCTAssertNil(empty.firstPoint)
        XCTAssertNil(empty.lastPoint)
    }

    /// 責務: 区間が1つでもあれば空でないことを確かめます。
    func testRouteWithSegmentIsNotEmpty() {
        XCTAssertFalse(route([Fixtures.segment([Fixtures.point(0, at: 0)])]).isEmpty)
    }

    /// 責務: 1点だけのルートで、最初の点と最後の点が同じ点になることを確かめます。
    func testSinglePointRouteHasSameFirstAndLast() {
        let only = Fixtures.point(5, at: 0)
        let single = route([Fixtures.segment([only])])
        XCTAssertEqual(single.firstPoint, only)
        XCTAssertEqual(single.lastPoint, only)
        XCTAssertEqual(single.points, [only])
    }

    /// 責務: 点の列が全区間の点を区間の順に連結したものになることを確かめます。
    func testPointsConcatenateSegmentsInOrder() {
        let first = [Fixtures.point(0, at: 0), Fixtures.point(1, at: 1)]
        let second = [Fixtures.point(2, at: 50)]
        let third = [Fixtures.point(3, at: 100), Fixtures.point(4, at: 101)]
        let joined = route([Fixtures.segment(first), Fixtures.segment(second, precision: .approximate), Fixtures.segment(third)])
        XCTAssertEqual(joined.points.map(\.sequence), [0, 1, 2, 3, 4])
        XCTAssertEqual(joined.firstPoint?.sequence, 0)
        XCTAssertEqual(joined.lastPoint?.sequence, 4)
    }

    /// 責務: 先頭の区間の点が空でも、点のある最初の区間から最初の点を取ることを確かめます。
    func testFirstPointSkipsLeadingEmptySegments() {
        let withPoints = Fixtures.segment([Fixtures.point(7, at: 0), Fixtures.point(8, at: 1)])
        let joined = route([Fixtures.segment([]), Fixtures.segment([]), withPoints])
        XCTAssertEqual(joined.firstPoint?.sequence, 7)
        XCTAssertEqual(joined.lastPoint?.sequence, 8)
    }

    /// 責務: 末尾の区間の点が空でも、点のある最後の区間から最後の点を取ることを確かめます。
    func testLastPointSkipsTrailingEmptySegments() {
        let withPoints = Fixtures.segment([Fixtures.point(1, at: 0), Fixtures.point(2, at: 1)])
        let joined = route([withPoints, Fixtures.segment([]), Fixtures.segment([])])
        XCTAssertEqual(joined.firstPoint?.sequence, 1)
        XCTAssertEqual(joined.lastPoint?.sequence, 2)
    }

    /// 責務: すべての区間の点が空なら、区間はあっても最初・最後の点が nil であることを確かめます。
    func testSegmentsWithoutPointsHaveNoFirstOrLast() {
        let joined = route([Fixtures.segment([]), Fixtures.segment([])])
        XCTAssertFalse(joined.isEmpty)
        XCTAssertNil(joined.firstPoint)
        XCTAssertNil(joined.lastPoint)
        XCTAssertEqual(joined.points, [])
    }

    /// 責務: 全点数と除外数が、渡した値のまま保たれることを確かめます。
    func testCountsArePreserved() {
        let value = DrivingRoute(segments: [], totalFixCount: 9, excludedFixCount: 4)
        XCTAssertEqual(value.totalFixCount, 9)
        XCTAssertEqual(value.excludedFixCount, 4)
    }
}
