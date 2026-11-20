import XCTest
@testable import ProjectZD8

/// `VehicleSpeedTimeline` の並べ替え・除外・範囲の取り出し・前後のサンプルの取得を検証します。
final class VehicleSpeedTimelineTests: XCTestCase {
    /// 責務: 時刻と車速からサンプルを作ります。
    private func sample(_ time: TimeInterval, _ kph: Double) -> VehicleSpeedSample {
        VehicleSpeedSample(time: time, kph: kph)
    }

    /// 責務: 時刻 10・20・30・40 のサンプルを持つ時系列を作ります。
    private func makeTimeline() -> VehicleSpeedTimeline {
        VehicleSpeedTimeline(samples: [sample(10, 1), sample(20, 2), sample(30, 3), sample(40, 4)])
    }

    /// 責務: 空の入力が空の時系列になることを確かめます。
    func testEmptyInput() {
        let timeline = VehicleSpeedTimeline(samples: [])
        XCTAssertTrue(timeline.isEmpty)
        XCTAssertTrue(timeline.samples.isEmpty)
        XCTAssertTrue(timeline.samples(in: 0...100).isEmpty)
        XCTAssertNil(timeline.lastSample(atOrBefore: 5))
        XCTAssertNil(timeline.firstSample(atOrAfter: 5))
    }

    /// 責務: 順不同の入力が時刻の昇順に並ぶことを確かめます。
    func testSamplesAreSortedByTime() {
        let timeline = VehicleSpeedTimeline(samples: [sample(30, 3), sample(10, 1), sample(20, 2)])
        XCTAssertEqual(timeline.samples.map(\.time), [10, 20, 30])
        XCTAssertEqual(timeline.samples.map(\.kph), [1, 2, 3])
        XCTAssertFalse(timeline.isEmpty)
    }

    /// 責務: 同じ時刻のサンプルは入力で後のものが残ることを確かめます。
    func testDuplicateTimesKeepTheLaterInput() {
        let timeline = VehicleSpeedTimeline(samples: [sample(10, 1), sample(20, 2), sample(10, 9), sample(10, 5)])
        XCTAssertEqual(timeline.samples, [sample(10, 5), sample(20, 2)])
    }

    /// 責務: 時刻か車速が有限でないサンプルが除かれることを確かめます。
    func testNonFiniteValuesAreDropped() {
        let timeline = VehicleSpeedTimeline(samples: [
            sample(.nan, 1), sample(.infinity, 2), sample(-.infinity, 3),
            sample(10, .nan), sample(11, .infinity), sample(12, -.infinity), sample(13, 4),
        ])
        XCTAssertEqual(timeline.samples, [sample(13, 4)])
    }

    /// 責務: 範囲の取り出しが両端を含み、範囲外を含まないことを確かめます。
    func testRangeIncludesBothEnds() {
        let timeline = makeTimeline()
        XCTAssertEqual(timeline.samples(in: 20...30).map(\.time), [20, 30])
        XCTAssertEqual(timeline.samples(in: 10...40).map(\.time), [10, 20, 30, 40])
        XCTAssertEqual(timeline.samples(in: 20.5...29.5).map(\.time), [])
        XCTAssertEqual(timeline.samples(in: 19.999...20.001).map(\.time), [20])
        XCTAssertEqual(timeline.samples(in: 25...25).map(\.time), [])
        XCTAssertEqual(timeline.samples(in: 30...30).map(\.time), [30])
    }

    /// 責務: 全体より外側の範囲や、全体を覆う範囲の取り出しを確かめます。
    func testRangeOutsideAndCoveringEverything() {
        let timeline = makeTimeline()
        XCTAssertTrue(timeline.samples(in: 0...9.999).isEmpty)
        XCTAssertTrue(timeline.samples(in: 40.001...99).isEmpty)
        XCTAssertEqual(timeline.samples(in: -1_000...1_000).count, 4)
    }

    /// 責務: lastSample が、同時刻を含めて指定時刻以前で最も新しいサンプルを返すことを確かめます。
    func testLastSampleAtOrBeforeIncludesEqualTime() {
        let timeline = makeTimeline()
        XCTAssertEqual(timeline.lastSample(atOrBefore: 20), sample(20, 2))
        XCTAssertEqual(timeline.lastSample(atOrBefore: 29.999), sample(20, 2))
        XCTAssertEqual(timeline.lastSample(atOrBefore: 1_000), sample(40, 4))
        XCTAssertEqual(timeline.lastSample(atOrBefore: 10), sample(10, 1))
        XCTAssertNil(timeline.lastSample(atOrBefore: 9.999))
    }

    /// 責務: firstSample が、同時刻を含めて指定時刻以後で最も古いサンプルを返すことを確かめます。
    func testFirstSampleAtOrAfterIncludesEqualTime() {
        let timeline = makeTimeline()
        XCTAssertEqual(timeline.firstSample(atOrAfter: 20), sample(20, 2))
        XCTAssertEqual(timeline.firstSample(atOrAfter: 20.001), sample(30, 3))
        XCTAssertEqual(timeline.firstSample(atOrAfter: -1_000), sample(10, 1))
        XCTAssertEqual(timeline.firstSample(atOrAfter: 40), sample(40, 4))
        XCTAssertNil(timeline.firstSample(atOrAfter: 40.001))
    }
}
