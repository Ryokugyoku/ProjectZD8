import XCTest
@testable import ProjectZD8

/// `RouteAnalysisTimeline.nearestPointIndex(to:within:)` の最近傍の探索を検証します。
@MainActor
final class RouteAnalysisTimelineTests: XCTestCase {
    private typealias Fixtures = RouteAnalysisTimelinePointFixtures

    private func nearest(_ seconds: [TimeInterval], to target: TimeInterval, within tolerance: TimeInterval) -> Int? {
        Fixtures.timeline(seconds).nearestPointIndex(to: Fixtures.base.addingTimeInterval(target), within: tolerance)
    }

    /// 責務: 点が無い時間の軸が nil を返すことを確かめます。
    func testEmptyTimelineReturnsNil() {
        XCTAssertNil(nearest([], to: 0, within: 100))
    }

    /// 責務: 時刻が点と一致する時に、その点の位置を返すことを確かめます。
    func testExactMatch() {
        XCTAssertEqual(nearest([0, 10, 20], to: 10, within: 2), 1)
    }

    /// 責務: 2点の間では近い方を返すことを確かめます。
    func testPicksNearerNeighbor() {
        XCTAssertEqual(nearest([0, 10], to: 3, within: 5), 0)
        XCTAssertEqual(nearest([0, 10], to: 7, within: 5), 1)
    }

    /// 責務: 等距離の時は前(時刻の早い方)の点を返すことを確かめます。
    func testEquidistantPrefersEarlierPoint() {
        XCTAssertEqual(nearest([0, 10], to: 5, within: 5), 0)
        XCTAssertEqual(nearest([0, 4, 10], to: 7, within: 5), 1)
    }

    /// 責務: 差が許容差とちょうど等しい点を採用することを確かめます(前側・後ろ側とも)。
    func testToleranceBoundaryIsInclusive() {
        XCTAssertEqual(nearest([10], to: 12, within: 2), 0)
        XCTAssertEqual(nearest([10], to: 8, within: 2), 0)
    }

    /// 責務: 差が許容差を少しでも超える時は nil になることを確かめます。
    func testBeyondToleranceReturnsNil() {
        XCTAssertNil(nearest([10], to: 12.001, within: 2))
        XCTAssertNil(nearest([10], to: 7.999, within: 2))
    }

    /// 責務: 許容差 0 では、時刻が完全に一致する点だけを採用することを確かめます。
    func testZeroToleranceRequiresExactMatch() {
        XCTAssertEqual(nearest([0, 10], to: 10, within: 0), 1)
        XCTAssertNil(nearest([0, 10], to: 10.001, within: 0))
    }

    /// 責務: 許容差が負または NaN の時は、点があっても nil になることを確かめます。
    func testNegativeOrNaNToleranceReturnsNil() {
        XCTAssertNil(nearest([10], to: 10, within: -1))
        XCTAssertNil(nearest([10], to: 10, within: -0.001))
        XCTAssertNil(nearest([10], to: 10, within: .nan))
    }

    /// 責務: 同じ時刻の点が複数ある時は、最初の点の位置を返すことを確かめます。
    func testSameTimestampReturnsFirstIndex() {
        XCTAssertEqual(nearest([0, 10, 10, 10, 20], to: 10, within: 1), 1)
        XCTAssertEqual(nearest([10, 10, 10], to: 10, within: 0), 0)
    }

    /// 責務: 最初の点より前、最後の点より後の時刻が、端の点(許容差以内)になることを確かめます。
    func testBeforeFirstAndAfterLast() {
        XCTAssertEqual(nearest([10, 20, 30], to: 9, within: 2), 0)
        XCTAssertEqual(nearest([10, 20, 30], to: 31, within: 2), 2)
        XCTAssertNil(nearest([10, 20, 30], to: 5, within: 2))
        XCTAssertNil(nearest([10, 20, 30], to: 35, within: 2))
    }

    /// 責務: 戻り値が `RouteAnalysisTimelinePoint.index` ではなく、配列の位置であることを確かめます。
    func testReturnsArrayPositionNotPointIndex() {
        let points = [Fixtures.point(100, at: 0), Fixtures.point(200, at: 10), Fixtures.point(300, at: 20)]
        let timeline = RouteAnalysisTimeline(points: points, alignment: .wallClock)
        XCTAssertEqual(timeline.nearestPointIndex(to: Fixtures.base.addingTimeInterval(10), within: 1), 1)
    }

    /// 責務: 点が多い(1,000点)時間の軸でも、すべての点を正しく探せることを確かめます。
    func testLargeTimelineFindsEveryPoint() {
        let seconds = (0..<1_000).map { TimeInterval($0) * 3 }
        let timeline = Fixtures.timeline(seconds)
        for index in stride(from: 0, to: 1_000, by: 37) {
            let date = Fixtures.base.addingTimeInterval(seconds[index] + 1)
            XCTAssertEqual(timeline.nearestPointIndex(to: date, within: 1.5), index)
        }
    }
}
