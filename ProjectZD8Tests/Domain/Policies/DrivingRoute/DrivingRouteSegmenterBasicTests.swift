import XCTest
@testable import ProjectZD8

/// `DrivingRouteSegmenter` の入力の形(空・1点・件数・点の写し・時刻の逆転)を設計書 §9 T3-1 で検証します。
@MainActor
final class DrivingRouteSegmenterBasicTests: XCTestCase {
    private typealias Fixtures = DrivingRouteTrackFixtures
    private let segmenter = DrivingRouteSegmenter()

    /// 責務: サンプルも事象も無い軌跡が、区間なし・件数0になることを確かめます。
    func testEmptyTrackHasNoSegments() {
        let route = segmenter.route(from: Fixtures.track([]))
        XCTAssertTrue(route.isEmpty)
        XCTAssertEqual(route.totalFixCount, 0)
        XCTAssertEqual(route.excludedFixCount, 0)
    }

    /// 責務: 事象だけの軌跡が、区間なし・件数0になることを確かめます。
    func testEventsOnlyTrackHasNoSegments() {
        let events = [Fixtures.event(0, at: 0, .recording), Fixtures.event(1, at: 5, .locationUnavailable)]
        let route = segmenter.route(from: Fixtures.track([], events: events))
        XCTAssertTrue(route.isEmpty)
        XCTAssertEqual(route.totalFixCount, 0)
        XCTAssertEqual(route.excludedFixCount, 0)
    }

    /// 責務: 1点だけの軌跡が、1点の1区間(正確)になることを確かめます。
    func testSinglePointMakesOneSegmentWithOnePoint() {
        let route = segmenter.route(from: Fixtures.track([Fixtures.sample(7, at: 0)]))
        XCTAssertEqual(Fixtures.sequences(of: route), [[7]])
        XCTAssertEqual(route.segments.first?.precision, .precise)
        XCTAssertEqual(route.totalFixCount, 1)
        XCTAssertEqual(route.excludedFixCount, 0)
    }

    /// 責務: 点の連番・座標・時刻・単調時刻・精度・標高が元のサンプルのまま写ることを確かめます。
    func testPointCarriesSampleValues() throws {
        let sample = Fixtures.sample(42, at: 3.5, x: 120, y: -80, accuracy: 12)
        let route = segmenter.route(from: Fixtures.track([sample]))
        let point = try XCTUnwrap(route.firstPoint)
        XCTAssertEqual(point.sequence, 42)
        XCTAssertEqual(point.coordinate.latitude, sample.fix.latitude)
        XCTAssertEqual(point.coordinate.longitude, sample.fix.longitude)
        XCTAssertEqual(point.observedAt, sample.fix.observedAt)
        XCTAssertEqual(point.monotonicNanoseconds, sample.fix.monotonicNanoseconds)
        XCTAssertEqual(point.horizontalAccuracyMeters, 12)
        XCTAssertEqual(point.altitudeMeters, 40)
        XCTAssertEqual(point.verticalAccuracyMeters, 3)
    }

    /// 責務: 1秒おきの連続した点が、1つの区間に順序のまま並ぶことを確かめます。
    func testContinuousPointsFormOneOrderedSegment() {
        let samples = (0..<20).map { Fixtures.sample(Int64($0), at: TimeInterval($0), x: Double($0) * 5) }
        let route = segmenter.route(from: Fixtures.track(samples))
        XCTAssertEqual(Fixtures.sequences(of: route), [Array(0..<20).map(Int64.init)])
        XCTAssertEqual(route.totalFixCount, 20)
        XCTAssertEqual(route.excludedFixCount, 0)
    }

    /// 責務: 時刻が同じ2点(時間差 0)の間で切ることを確かめます。
    func testZeroTimeDifferenceCutsTheLine() {
        let samples = [Fixtures.sample(0, at: 5), Fixtures.sample(1, at: 5)]
        let route = segmenter.route(from: Fixtures.track(samples))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0], [1]])
    }

    /// 責務: 時刻が戻る2点(時間差が負)の間で切り、その後は新しい区間でつながることを確かめます。
    func testNegativeTimeDifferenceCutsTheLine() {
        let samples = [Fixtures.sample(0, at: 10), Fixtures.sample(1, at: 5), Fixtures.sample(2, at: 6)]
        let route = segmenter.route(from: Fixtures.track(samples))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0], [1, 2]])
    }

    /// 責務: 切れ目ごとに区間が分かれ、すべての点がどこかの区間に残る(点を失わない)ことを確かめます。
    func testEveryKeptPointBelongsToExactlyOneSegment() {
        let times: [TimeInterval] = [0, 1, 2, 30, 31, 100, 101, 102]
        let samples = times.enumerated().map { Fixtures.sample(Int64($0.offset), at: $0.element) }
        let route = segmenter.route(from: Fixtures.track(samples))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0, 1, 2], [3, 4], [5, 6, 7]])
        XCTAssertEqual(route.points.count, 8)
    }

    /// 責務: 除いた点と残した点の件数が、全点数と除外数に分かれて数えられることを確かめます。
    func testCountsSeparateExcludedFromTotal() {
        let samples = [
            Fixtures.sample(0, at: 0),
            Fixtures.sample(1, at: 1, accuracy: 80),
            Fixtures.sample(2, at: 2, accuracy: 51),
            Fixtures.sample(3, at: 3)
        ]
        let route = segmenter.route(from: Fixtures.track(samples))
        XCTAssertEqual(route.totalFixCount, 4)
        XCTAssertEqual(route.excludedFixCount, 2)
        XCTAssertEqual(Fixtures.sequences(of: route), [[0, 3]])
    }

    /// 責務: すべての点が精度で除かれると、区間なし・全点数と除外数が同じになることを確かめます。
    func testAllPointsExcludedLeavesNoSegments() {
        let samples = (0..<3).map { Fixtures.sample(Int64($0), at: TimeInterval($0), accuracy: 100) }
        let route = segmenter.route(from: Fixtures.track(samples))
        XCTAssertTrue(route.isEmpty)
        XCTAssertEqual(route.totalFixCount, 3)
        XCTAssertEqual(route.excludedFixCount, 3)
    }
}
