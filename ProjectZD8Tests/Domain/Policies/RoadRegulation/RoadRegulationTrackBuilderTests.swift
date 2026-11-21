import XCTest
@testable import ProjectZD8

/// `RoadRegulationTrackBuilder.build` が、位置のサンプルを選んだ時刻軸の軌跡へ直し、使えない点を捨てて数えることを検証します。
final class RoadRegulationTrackBuilderTests: XCTestCase {
    private let builder = RoadRegulationTrackBuilder(thresholds: .standard)
    private typealias Fixtures = RoadRegulationTimeSourceFixtures

    /// 責務: 空の入力が空の軌跡・捨てた数 0 になることを確かめます。
    func testEmptyInput() {
        for axis in [RoadRegulationTimeAxis.monotonic, .wallClock] {
            let result = builder.build([], axis: axis)
            XCTAssertTrue(result.points.isEmpty)
            XCTAssertEqual(result.droppedCount, 0)
        }
    }

    /// 責務: 精度 50 m ちょうどは残り、50.01 m は捨てて数えられ、順序が保たれることを確かめます。
    func testAccuracyBoundaryKeepsFiftyAndDropsOverFifty() {
        let samples = [
            Fixtures.location(1, monotonicSeconds: 100, accuracy: 50),
            Fixtures.location(2, monotonicSeconds: 101, accuracy: 50.01),
            Fixtures.location(3, monotonicSeconds: 102, accuracy: 5),
            Fixtures.location(4, monotonicSeconds: 103, accuracy: 0),
            Fixtures.location(5, monotonicSeconds: 104, accuracy: 500),
        ]
        let result = builder.build(samples, axis: .monotonic)
        XCTAssertEqual(result.points.map(\.sequence), [1, 3, 4])
        XCTAssertEqual(result.droppedCount, 2)
    }

    /// 責務: 時刻が逆行する点が捨てられて数えられ、前後の正常な点は残ることを確かめます。
    func testBackwardsTimePointIsDropped() {
        for axis in [RoadRegulationTimeAxis.monotonic, .wallClock] {
            let samples = [
                Fixtures.location(1, monotonicSeconds: 100),
                Fixtures.location(2, monotonicSeconds: 99),
                Fixtures.location(3, monotonicSeconds: 101),
            ]
            let result = builder.build(samples, axis: axis)
            XCTAssertEqual(result.points.map(\.sequence), [1, 3], "\(axis)")
            XCTAssertEqual(result.droppedCount, 1, "\(axis)")
        }
    }

    /// 責務: 直前に残した点と同じ時刻の点は残る(捨てない)ことを確かめます。
    func testEqualTimePointIsKept() {
        let samples = [
            Fixtures.location(1, monotonicSeconds: 100),
            Fixtures.location(2, monotonicSeconds: 100),
            Fixtures.location(3, monotonicSeconds: 101),
        ]
        let result = builder.build(samples, axis: .monotonic)
        XCTAssertEqual(result.points.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(result.droppedCount, 0)
    }

    /// 責務: 捨てた点の後の比較が、直前に「残した」点との比較になることを確かめます(精度で捨てた点の時刻は基準にならない)。
    func testBackwardsComparisonUsesLastKeptPoint() {
        let samples = [
            Fixtures.location(1, monotonicSeconds: 100),
            Fixtures.location(2, monotonicSeconds: 120, accuracy: 80),
            Fixtures.location(3, monotonicSeconds: 105),
        ]
        let result = builder.build(samples, axis: .monotonic)
        XCTAssertEqual(result.points.map(\.sequence), [1, 3])
        XCTAssertEqual(result.droppedCount, 1)
    }

    /// 責務: 既定のしきい値で作れることを確かめます。
    func testDefaultThresholdsInitializer() {
        let result = RoadRegulationTrackBuilder().build([Fixtures.location(1, monotonicSeconds: 100, accuracy: 51)], axis: .monotonic)
        XCTAssertEqual(result.droppedCount, 1)
    }

    /// 責務: 時刻の値が、単調時計の軸では単調時刻(秒)、実時間の軸では 1970 年からの秒になることを確かめます。
    func testTimeValuesAreExact() throws {
        let sample = Fixtures.location(1, monotonicSeconds: 100, offset: 3)
        let monotonic = try XCTUnwrap(builder.build([sample], axis: .monotonic).points.first)
        XCTAssertEqual(monotonic.time, 100, accuracy: 1e-6)
        let wall = try XCTUnwrap(builder.build([sample], axis: .wallClock).points.first)
        XCTAssertEqual(wall.time, sample.fix.observedAt.timeIntervalSince1970, accuracy: 1e-6)
    }

    /// 責務: 軌跡の時刻が昇順で、点の順序が入力の連番の順になることを確かめます。
    func testPointsAreInInputOrderWithAscendingTime() {
        let samples = (1...6).map { Fixtures.location(Int64($0), monotonicSeconds: 100 + Double($0)) }
        for axis in [RoadRegulationTimeAxis.monotonic, .wallClock] {
            let points = builder.build(samples, axis: axis).points
            XCTAssertEqual(points.map(\.sequence), [1, 2, 3, 4, 5, 6], "\(axis)")
            XCTAssertEqual(points.map(\.time), points.map(\.time).sorted(), "\(axis)")
        }
    }

    /// 責務: 単調時計の軸では時刻が単調時刻(秒)に、実時間の軸では実時間に従うことを、間隔で確かめます。
    func testTimeFollowsTheSelectedAxis() throws {
        let samples = [
            Fixtures.location(1, monotonicSeconds: 100, offset: 0),
            Fixtures.location(2, monotonicSeconds: 110, offset: 5),
        ]
        let monotonic = builder.build(samples, axis: .monotonic).points
        let monotonicFirst = try XCTUnwrap(monotonic.first)
        let monotonicLast = try XCTUnwrap(monotonic.last)
        XCTAssertEqual(monotonicLast.time - monotonicFirst.time, 10, accuracy: 1e-6)
        XCTAssertEqual(monotonicFirst.time, 100, accuracy: 1e-6)
        let wall = builder.build(samples, axis: .wallClock).points
        let wallFirst = try XCTUnwrap(wall.first)
        let wallLast = try XCTUnwrap(wall.last)
        XCTAssertEqual(wallLast.time - wallFirst.time, 15, accuracy: 1e-6)
    }

    /// 責務: 位置・精度・進行方向・GPS 速度・実時間が点へ写ることを確かめます。
    func testPointCarriesFixFields() throws {
        let sample = Fixtures.location(9, monotonicSeconds: 100, accuracy: 7, latitude: 26.25)
        let point = try XCTUnwrap(builder.build([sample], axis: .monotonic).points.first)
        XCTAssertEqual(point.sequence, 9)
        XCTAssertEqual(point.coordinate.latitude, 26.25)
        XCTAssertEqual(point.coordinate.longitude, 127.7)
        XCTAssertEqual(point.horizontalAccuracyMeters, 7)
        XCTAssertEqual(point.courseDegrees, 90)
        XCTAssertEqual(point.gpsSpeedMetersPerSecond, 8)
        XCTAssertEqual(point.observedAt, sample.fix.observedAt)
    }

    /// 責務: 全点が使えない時に、空の軌跡と全点の数が返ることを確かめます。
    func testAllPointsDroppedReturnsEmptyTrack() {
        let samples = (1...3).map { Fixtures.location(Int64($0), monotonicSeconds: 100 + Double($0), accuracy: 80) }
        let result = builder.build(samples, axis: .monotonic)
        XCTAssertTrue(result.points.isEmpty)
        XCTAssertEqual(result.droppedCount, 3)
    }
}
