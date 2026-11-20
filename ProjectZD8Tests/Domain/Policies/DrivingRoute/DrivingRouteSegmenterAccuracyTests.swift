import XCTest
@testable import ProjectZD8

/// `DrivingRouteSegmenter` の精度による除外と、精度の段階(正確・概略)の決め方・切替を設計書 §2.1・§9 T3-1 で検証します。
@MainActor
final class DrivingRouteSegmenterAccuracyTests: XCTestCase {
    private typealias Fixtures = DrivingRouteTrackFixtures
    private let segmenter = DrivingRouteSegmenter()
    private let approximateFromStart = [Fixtures.event(0, at: -100, .recordingWithReducedAccuracy)]

    /// 責務: 1点だけのルートを作り、その点が残るかを返します。
    private func isKept(accuracy: Double, events: [ConnectionSessionLocationEvent] = []) -> Bool {
        let route = segmenter.route(from: Fixtures.track([Fixtures.sample(0, at: 0, accuracy: accuracy)], events: events))
        return !route.isEmpty
    }

    /// 責務: 正確な位置で、水平精度 50.0 m ちょうどは残し、50.01 m は除いて数えることを確かめます。
    func testPreciseAccuracyBoundary() {
        XCTAssertTrue(isKept(accuracy: 50.0))
        XCTAssertFalse(isKept(accuracy: 50.01))
        XCTAssertTrue(isKept(accuracy: 49.99))
        let excluded = segmenter.route(from: Fixtures.track([Fixtures.sample(0, at: 0, accuracy: 50.01)]))
        XCTAssertEqual(excluded.excludedFixCount, 1)
    }

    /// 責務: 概略の位置で、水平精度 5,000 m ちょうどは残し、5,000.01 m は除くことを確かめます。
    func testApproximateAccuracyBoundary() {
        XCTAssertTrue(isKept(accuracy: 5_000.0, events: approximateFromStart))
        XCTAssertFalse(isKept(accuracy: 5_000.01, events: approximateFromStart))
        XCTAssertTrue(isKept(accuracy: 4_999.99, events: approximateFromStart))
    }

    /// 責務: 概略の位置なら、正確では除かれる 60 m の精度の点が残ることを確かめます。
    func testApproximateStageKeepsPointsThatPreciseWouldExclude() {
        XCTAssertFalse(isKept(accuracy: 60))
        XCTAssertTrue(isKept(accuracy: 60, events: approximateFromStart))
    }

    /// 責務: 精度 0 m の点も残すことを確かめます。
    func testZeroAccuracyIsKept() {
        XCTAssertTrue(isKept(accuracy: 0))
    }

    /// 責務: 悪い点を挟んでも、残った前後の点の時間差が 10 s 以内ならつなぐことを確かめます。
    func testExcludedPointBetweenWithinTenSecondsKeepsConnection() {
        let samples = [Fixtures.sample(0, at: 0), Fixtures.sample(1, at: 5, accuracy: 60), Fixtures.sample(2, at: 10)]
        let route = segmenter.route(from: Fixtures.track(samples))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0, 2]])
        XCTAssertEqual(route.excludedFixCount, 1)
    }

    /// 責務: 悪い点を挟んで、残った前後の点の時間差が 10 s を超えると切ることを確かめます。
    func testExcludedPointBetweenBeyondTenSecondsCuts() {
        let samples = [Fixtures.sample(0, at: 0), Fixtures.sample(1, at: 5, accuracy: 60), Fixtures.sample(2, at: 10.001)]
        let route = segmenter.route(from: Fixtures.track(samples))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0], [2]])
    }

    /// 責務: 悪い点が続いても(3点)、前後の差が 10 s 以内ならつなぐことを確かめます。
    func testConsecutiveExcludedPointsAreSkipped() {
        let bad = [1, 2, 3].map { Fixtures.sample(Int64($0), at: TimeInterval($0) * 2, accuracy: 90) }
        let samples = [Fixtures.sample(0, at: 0)] + bad + [Fixtures.sample(4, at: 8)]
        let route = segmenter.route(from: Fixtures.track(samples))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0, 4]])
        XCTAssertEqual(route.excludedFixCount, 3)
    }

    /// 責務: 取得事象が無い(記録中以外の事象だけ)時は、正確として扱うことを確かめます。
    func testNoAcquisitionEventDefaultsToPrecise() throws {
        let events = [Fixtures.event(0, at: -10, .authorizationDenied)]
        XCTAssertFalse(isKept(accuracy: 60, events: events))
        let route = segmenter.route(from: Fixtures.track([Fixtures.sample(0, at: 0)], events: events))
        XCTAssertEqual(try XCTUnwrap(route.segments.first).precision, .precise)
    }

    /// 責務: 最初の取得事象より前の点は、その事象の精度の段階に従う(概略)ことを確かめます。
    func testPointBeforeFirstAcquisitionEventFollowsIt() throws {
        let events = [Fixtures.event(0, at: 100, .recordingWithReducedAccuracy)]
        let samples = [Fixtures.sample(0, at: 0, accuracy: 60), Fixtures.sample(1, at: 20, accuracy: 60)]
        let route = segmenter.route(from: Fixtures.track(samples, events: events))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0, 1]])
        XCTAssertEqual(try XCTUnwrap(route.segments.first).precision, .approximate)
    }

    /// 責務: 最初の取得事象より前の点は、その事象が記録中なら正確として扱うことを確かめます。
    func testPointBeforeFirstRecordingEventIsPrecise() throws {
        let events = [Fixtures.event(0, at: 100, .recording)]
        let route = segmenter.route(from: Fixtures.track([Fixtures.sample(0, at: 0)], events: events))
        XCTAssertEqual(try XCTUnwrap(route.segments.first).precision, .precise)
    }

    /// 責務: 点の精度の段階が、その時刻以前で最後の取得事象で決まり、切替の所で切ることを確かめます。
    func testPrecisionFollowsLatestAcquisitionEventAndCutsOnSwitch() {
        let events = [
            Fixtures.event(0, at: 0, .recording),
            Fixtures.event(1, at: 50, .recordingWithReducedAccuracy),
            Fixtures.event(2, at: 100, .recording)
        ]
        let samples = [Fixtures.sample(0, at: 40), Fixtures.sample(1, at: 60), Fixtures.sample(2, at: 110)]
        let route = segmenter.route(from: Fixtures.track(samples, events: events))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0], [1], [2]])
        XCTAssertEqual(route.segments.map(\.precision), [.precise, .approximate, .precise])
    }

    /// 責務: 事象の時刻と同じ時刻の点は新しい段階に含まれ、直前(0.001 s 前)の点は前の段階であることを確かめます。
    func testAcquisitionEventAtPointTimeAppliesToThatPoint() {
        let events = [Fixtures.event(0, at: 0, .recording), Fixtures.event(1, at: 50, .recordingWithReducedAccuracy)]
        let samples = [Fixtures.sample(0, at: 49.999), Fixtures.sample(1, at: 50)]
        let route = segmenter.route(from: Fixtures.track(samples, events: events))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0], [1]])
        XCTAssertEqual(route.segments.map(\.precision), [.precise, .approximate])
    }

    /// 責務: 精度の段階が同じ事象の再記録では切らず、区間の精度もそのままであることを確かめます。
    func testRepeatedSamePrecisionEventDoesNotCut() {
        let events = [Fixtures.event(0, at: 0, .recording), Fixtures.event(1, at: 5, .recording)]
        let samples = [Fixtures.sample(0, at: 2), Fixtures.sample(1, at: 8)]
        let route = segmenter.route(from: Fixtures.track(samples, events: events))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0, 1]])
        XCTAssertEqual(route.segments.map(\.precision), [.precise])
    }

    /// 責務: 精度の段階の切替が、悪い点を除いた後の前後の点で判定されることを確かめます。
    func testPrecisionSwitchIsJudgedBetweenKeptNeighbors() {
        let events = [Fixtures.event(0, at: 0, .recording), Fixtures.event(1, at: 6, .recordingWithReducedAccuracy)]
        let samples = [Fixtures.sample(0, at: 2), Fixtures.sample(1, at: 4, accuracy: 70), Fixtures.sample(2, at: 8)]
        let route = segmenter.route(from: Fixtures.track(samples, events: events))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0], [2]])
        XCTAssertEqual(route.segments.map(\.precision), [.precise, .approximate])
    }
}
