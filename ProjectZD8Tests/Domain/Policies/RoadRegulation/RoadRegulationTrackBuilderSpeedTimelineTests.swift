import XCTest
@testable import ProjectZD8

/// `RoadRegulationTrackBuilder.speedTimeline` が、車速の観測を選んだ時刻軸の時系列へ直すことを検証します。
final class RoadRegulationTrackBuilderSpeedTimelineTests: XCTestCase {
    private let builder = RoadRegulationTrackBuilder(thresholds: .standard)
    private typealias Fixtures = RoadRegulationTimeSourceFixtures

    /// 責務: 空の入力が空の時系列になることを確かめます。
    func testEmptyInput() {
        XCTAssertTrue(builder.speedTimeline([], axis: .monotonic).isEmpty)
        XCTAssertTrue(builder.speedTimeline([], axis: .wallClock).isEmpty)
    }

    /// 責務: 順不同の観測が時刻の昇順の時系列になり、車速が保たれることを確かめます。
    func testObservationsAreOrderedAndKeepSpeed() {
        let observations = [
            Fixtures.speed(monotonicSeconds: 102, kph: 30),
            Fixtures.speed(monotonicSeconds: 100, kph: 10),
            Fixtures.speed(monotonicSeconds: 101, kph: 20),
        ]
        for axis in [RoadRegulationTimeAxis.monotonic, .wallClock] {
            let samples = builder.speedTimeline(observations, axis: axis).samples
            XCTAssertEqual(samples.map(\.kph), [10, 20, 30], "\(axis)")
            XCTAssertEqual((samples.last?.time ?? 0) - (samples.first?.time ?? 0), 2, accuracy: 1e-6, "\(axis)")
        }
    }

    /// 責務: 単調時計の軸で、単調時刻の無い観測が除かれることを確かめます。
    func testMonotonicAxisDropsObservationsWithoutMonotonicTime() {
        let observations = [
            Fixtures.speed(monotonicSeconds: 100, kph: 10),
            Fixtures.speed(monotonicSeconds: nil, offset: 101, kph: 99),
            Fixtures.speed(monotonicSeconds: 102, kph: 30),
        ]
        XCTAssertEqual(builder.speedTimeline(observations, axis: .monotonic).samples.map(\.kph), [10, 30])
        XCTAssertEqual(builder.speedTimeline(observations, axis: .wallClock).samples.map(\.kph), [10, 99, 30])
    }

    /// 責務: 時刻の軸が違えば、実時間とずれのある観測の時刻の間隔が軸どおりになることを確かめます。
    func testTimeSpacingFollowsAxis() {
        let observations = [
            Fixtures.speed(monotonicSeconds: 100, offset: 0, kph: 10),
            Fixtures.speed(monotonicSeconds: 110, offset: 5, kph: 20),
        ]
        let monotonic = builder.speedTimeline(observations, axis: .monotonic).samples
        XCTAssertEqual(monotonic[1].time - monotonic[0].time, 10, accuracy: 1e-6)
        let wall = builder.speedTimeline(observations, axis: .wallClock).samples
        XCTAssertEqual(wall[1].time - wall[0].time, 15, accuracy: 1e-6)
    }

    /// 責務: 位置の軌跡と車速の時系列が、同じ瞬間に同じ時刻の値になる(同じ軸で比べられる)ことを確かめます。
    func testTimelineSharesTimeAxisWithTrack() throws {
        let location = Fixtures.location(1, monotonicSeconds: 105, offset: 3)
        let observation = Fixtures.speed(monotonicSeconds: 105, offset: 3, kph: 42)
        for axis in [RoadRegulationTimeAxis.monotonic, .wallClock] {
            let point = try XCTUnwrap(builder.build([location], axis: axis).points.first)
            let sample = try XCTUnwrap(builder.speedTimeline([observation], axis: axis).samples.first)
            XCTAssertEqual(point.time, sample.time, accuracy: 1e-6, "\(axis)")
        }
    }

    /// 責務: 同じ時刻の観測は、後の値が残ることを確かめます。
    func testEqualTimeKeepsLaterObservation() {
        let observations = [
            Fixtures.speed(monotonicSeconds: 100, kph: 10),
            Fixtures.speed(monotonicSeconds: 100, kph: 20),
        ]
        for axis in [RoadRegulationTimeAxis.monotonic, .wallClock] {
            XCTAssertEqual(builder.speedTimeline(observations, axis: axis).samples.map(\.kph), [20], "\(axis)")
        }
    }

    /// 責務: 時刻の値が、単調時計の軸では単調時刻(秒)、実時間の軸では 1970 年からの秒になることを確かめます。
    func testTimeValuesAreExact() throws {
        let observation = Fixtures.speed(monotonicSeconds: 100, offset: 3, kph: 10)
        let monotonic = try XCTUnwrap(builder.speedTimeline([observation], axis: .monotonic).samples.first)
        XCTAssertEqual(monotonic.time, 100, accuracy: 1e-6)
        let wall = try XCTUnwrap(builder.speedTimeline([observation], axis: .wallClock).samples.first)
        XCTAssertEqual(wall.time, observation.observedAt.timeIntervalSince1970, accuracy: 1e-6)
    }

    /// 責務: 有限でない車速と、0〜255 の範囲外(負・256)が除かれることを確かめます。
    func testInvalidSpeedsAreDropped() {
        let observations = [
            Fixtures.speed(monotonicSeconds: 100, kph: .nan),
            Fixtures.speed(monotonicSeconds: 101, kph: .infinity),
            Fixtures.speed(monotonicSeconds: 102, kph: -5),
            Fixtures.speed(monotonicSeconds: 103, kph: 0),
            Fixtures.speed(monotonicSeconds: 104, kph: 55),
            Fixtures.speed(monotonicSeconds: 105, kph: 256),
            Fixtures.speed(monotonicSeconds: 106, kph: 255),
        ]
        XCTAssertEqual(builder.speedTimeline(observations, axis: .monotonic).samples.map(\.kph), [0, 55, 255])
    }
}
