import Foundation
import XCTest
@testable import ProjectZD8

/// 地図の座標から、最も近い位置の時刻を求める規則(200 m 以内)を検証します(設計書 §2.3「地図 → グラフ」)。
///
/// 距離は製品の座標計算と独立な式で置くため、境界はちょうどの値でなく 199 m と 201 m で確かめます。
@MainActor
final class RouteAnalysisCursorResolverReverseTests: XCTestCase {
    private typealias Fixtures = RouteAnalysisRouteTimelineFixtures

    /// 検証対象です。
    private let resolver = RouteAnalysisCursorResolver()
    /// 東へ 0 m・1,000 m・2,000 m(0 s・1 s・2 s)の3点の時間の軸です。
    private let timeline = Fixtures.timeline(segments: [[0, 1_000, 2_000]])

    /// 責務: 200 m の少し内側(199 m)の最も近い点の時刻を返すことを確かめます。
    func testNearestPointWithinLimitGivesItsDate() {
        let date = resolver.date(nearestTo: Fixtures.coordinates.point(x: 1_199, y: 0), in: timeline)

        XCTAssertEqual(date, timeline.points[1].date)
    }

    /// 責務: 最も近い点まで 200 m の少し外側(201 m)なら `nil` になることを確かめます。
    func testNearestPointBeyondLimitGivesNil() {
        XCTAssertNil(resolver.date(nearestTo: Fixtures.coordinates.point(x: 1_201, y: 0), in: timeline))
    }

    /// 責務: 200 m 以内に複数の点があれば、最も近い点の時刻を返すことを確かめます。
    func testPicksClosestOfSeveralPoints() {
        let close = Fixtures.timeline(segments: [[0, 300]])

        let date = resolver.date(nearestTo: Fixtures.coordinates.point(x: 180, y: 0), in: close)

        XCTAssertEqual(date, close.points[1].date)
    }

    /// 責務: 北向きにずれた座標でも、距離(190 m)で判定することを確かめます。
    func testDistanceIsMeasuredInBothAxes() {
        let date = resolver.date(nearestTo: Fixtures.coordinates.point(x: 2_000, y: 190), in: timeline)

        XCTAssertEqual(date, timeline.points[2].date)
    }

    /// 責務: 点の無い時間の軸では `nil` になることを確かめます。
    func testEmptyTimelineGivesNil() {
        XCTAssertNil(resolver.date(nearestTo: Fixtures.coordinates.point(x: 0, y: 0), in: Fixtures.timeline(segments: [])))
    }

    /// 責務: 初期化で渡した距離の上限(50 m)が、内側(40 m)と外側(60 m)の判定に使われることを確かめます。
    func testCustomDistanceLimitIsApplied() {
        let strict = RouteAnalysisCursorResolver(maximumSelectionDistanceMeters: 50)

        XCTAssertEqual(strict.date(nearestTo: Fixtures.coordinates.point(x: 40, y: 0), in: timeline), timeline.points[0].date)
        XCTAssertNil(strict.date(nearestTo: Fixtures.coordinates.point(x: 60, y: 0), in: timeline))
    }

    /// 責務: 2点から同じ距離(経度 ±0.0005 度、約 56 m)なら、先の点の時刻を返すことを確かめます。
    func testEquidistantPrefersEarlierPoint() throws {
        let west = try XCTUnwrap(GeoCoordinate(latitude: 0, longitude: -0.000_5))
        let east = try XCTUnwrap(GeoCoordinate(latitude: 0, longitude: 0.000_5))
        let center = try XCTUnwrap(GeoCoordinate(latitude: 0, longitude: 0))
        let pair = Fixtures.timeline(points: [
            RouteAnalysisTimelinePoint(
                index: 0, sequence: 0, segmentIndex: 0, precision: .precise, coordinate: west, date: Fixtures.date(0), altitudeMeters: nil
            ),
            RouteAnalysisTimelinePoint(
                index: 1, sequence: 1, segmentIndex: 0, precision: .precise, coordinate: east, date: Fixtures.date(1), altitudeMeters: nil
            )
        ])

        XCTAssertEqual(resolver.date(nearestTo: center, in: pair), Fixtures.date(0))
    }
}
