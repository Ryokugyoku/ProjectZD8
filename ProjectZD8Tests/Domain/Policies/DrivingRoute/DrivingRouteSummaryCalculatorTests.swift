import XCTest
@testable import ProjectZD8

/// `DrivingRouteSummaryCalculator` の長さ・記録時間・記録できた割合を設計書 §3.1・§9 T3-2 で検証します。
@MainActor
final class DrivingRouteSummaryCalculatorTests: XCTestCase {
    private typealias Fixtures = DrivingRoutePointFixtures
    private let calculator = DrivingRouteSummaryCalculator()
    private let start = DrivingRouteTrackFixtures.date(0)

    /// 責務: 基準日時から指定秒後の日時を返します。
    private func date(_ seconds: TimeInterval) -> Date {
        DrivingRouteTrackFixtures.date(seconds)
    }

    /// 責務: 東向きに 0 → 100 → 300 m の点を持つ、時刻 0〜20 s の区間 A を返します。
    private func segmentA() -> DrivingRouteSegment {
        Fixtures.segment([
            Fixtures.point(0, at: 0, x: 0), Fixtures.point(1, at: 10, x: 100), Fixtures.point(2, at: 20, x: 300)
        ])
    }

    /// 責務: 東向きに 1,000 → 1,500 m の点を持つ、時刻 50〜80 s の区間 B を返します。
    private func segmentB() -> DrivingRouteSegment {
        Fixtures.segment([Fixtures.point(3, at: 50, x: 1_000), Fixtures.point(4, at: 80, x: 1_500)])
    }

    /// 責務: 長さが区間内の隣り合う点の距離の和で、区間の切れ目(300 → 1,000 m)を含まないことを確かめます。
    func testLengthSumsWithinSegmentsOnly() {
        let summary = calculator.summary(of: Fixtures.route([segmentA(), segmentB()]), sessionStartedAt: start, sessionEndedAt: date(100))
        XCTAssertEqual(summary.lengthMeters, 800, accuracy: 1.0)
    }

    /// 責務: 長さが、直線ではなく折れた経路に沿って測られる(東 300 m → 北 400 m で 700 m)ことを確かめます。
    func testLengthFollowsThePolyline() {
        let segment = Fixtures.segment([
            Fixtures.point(0, at: 0, x: 0, y: 0), Fixtures.point(1, at: 10, x: 300, y: 0), Fixtures.point(2, at: 20, x: 300, y: 400)
        ])
        let summary = calculator.summary(of: Fixtures.route([segment]), sessionStartedAt: start, sessionEndedAt: date(20))
        XCTAssertEqual(summary.lengthMeters, 700, accuracy: 1.0)
    }

    /// 責務: 1点だけの区間の長さと記録時間が 0 であることを確かめます。
    func testSinglePointSegmentContributesNothing() throws {
        let route = Fixtures.route([Fixtures.segment([Fixtures.point(0, at: 5, x: 50)])])
        let summary = calculator.summary(of: route, sessionStartedAt: start, sessionEndedAt: date(100))
        XCTAssertEqual(summary.lengthMeters, 0, accuracy: 1e-9)
        XCTAssertEqual(summary.recordedDuration, 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.coverageRatio), 0, accuracy: 1e-12)
    }

    /// 責務: 記録時間が、各区間の(最後 − 最初)の和(20 + 30 = 50 s)で、区間の間の空きを含まないことを確かめます。
    func testRecordedDurationSumsSegmentWidths() {
        let summary = calculator.summary(of: Fixtures.route([segmentA(), segmentB()]), sessionStartedAt: start, sessionEndedAt: date(100))
        XCTAssertEqual(summary.recordedDuration, 50, accuracy: 1e-9)
    }

    /// 責務: 割合が 記録時間 ÷ (終了 − 開始) = 50 ÷ 100 = 0.5 になることを確かめます。
    func testCoverageIsRecordedOverSessionDuration() throws {
        let summary = calculator.summary(of: Fixtures.route([segmentA(), segmentB()]), sessionStartedAt: start, sessionEndedAt: date(100))
        XCTAssertEqual(try XCTUnwrap(summary.coverageRatio), 0.5, accuracy: 1e-9)
    }

    /// 責務: 終了が nil の時は最後の点の時刻(80 s)を使い、50 ÷ 80 = 0.625 になることを確かめます。
    func testOpenSessionUsesLastPointTime() throws {
        let summary = calculator.summary(of: Fixtures.route([segmentA(), segmentB()]), sessionStartedAt: start, sessionEndedAt: nil)
        XCTAssertEqual(try XCTUnwrap(summary.coverageRatio), 0.625, accuracy: 1e-9)
    }

    /// 責務: 終了が nil で最後の点も開始以前なら、分母が 0 以下で割合が nil になることを確かめます。
    func testOpenSessionWithLastPointNotAfterStartHasNoRatio() {
        let route = Fixtures.route([Fixtures.segment([Fixtures.point(0, at: -5)])])
        XCTAssertNil(calculator.summary(of: route, sessionStartedAt: start, sessionEndedAt: nil).coverageRatio)
        let atStart = Fixtures.route([Fixtures.segment([Fixtures.point(0, at: 0)])])
        XCTAssertNil(calculator.summary(of: atStart, sessionStartedAt: start, sessionEndedAt: nil).coverageRatio)
    }

    /// 責務: 終了が開始と同じ、または開始より前なら、割合が nil になることを確かめます。
    func testNonPositiveSessionDurationHasNoRatio() {
        let route = Fixtures.route([segmentA()])
        XCTAssertNil(calculator.summary(of: route, sessionStartedAt: start, sessionEndedAt: start).coverageRatio)
        XCTAssertNil(calculator.summary(of: route, sessionStartedAt: start, sessionEndedAt: date(-10)).coverageRatio)
    }

    /// 責務: 記録時間がセッションの時間を超える時は、割合を 1 に切り詰めることを確かめます。
    func testCoverageIsClampedToOne() throws {
        let summary = calculator.summary(of: Fixtures.route([segmentA(), segmentB()]), sessionStartedAt: start, sessionEndedAt: date(25))
        XCTAssertEqual(try XCTUnwrap(summary.coverageRatio), 1, accuracy: 1e-12)
        XCTAssertEqual(summary.recordedDuration, 50, accuracy: 1e-9)
    }

    /// 責務: 全時間を記録できた(0〜100 s の1区間)時に、割合がちょうど 1(100%)になることを確かめます。
    func testFullCoverageIsExactlyOne() throws {
        let segment = Fixtures.segment([Fixtures.point(0, at: 0), Fixtures.point(1, at: 100)])
        let summary = calculator.summary(of: Fixtures.route([segment]), sessionStartedAt: start, sessionEndedAt: date(100))
        XCTAssertEqual(try XCTUnwrap(summary.coverageRatio), 1, accuracy: 1e-12)
    }

    /// 責務: 空のルートが、長さ 0・記録時間 0・割合 0(分母が正の時)になることを確かめます。
    func testEmptyRouteSummary() throws {
        let empty = DrivingRoute(segments: [], totalFixCount: 0, excludedFixCount: 0)
        let summary = calculator.summary(of: empty, sessionStartedAt: start, sessionEndedAt: date(100))
        XCTAssertEqual(summary.lengthMeters, 0, accuracy: 1e-9)
        XCTAssertEqual(summary.recordedDuration, 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.coverageRatio), 0, accuracy: 1e-12)
    }

    /// 責務: 空のルートで終了が nil なら、分母が 0 で割合が nil になることを確かめます。
    func testEmptyRouteOfOpenSessionHasNoRatio() {
        let empty = DrivingRoute(segments: [], totalFixCount: 0, excludedFixCount: 0)
        let summary = calculator.summary(of: empty, sessionStartedAt: start, sessionEndedAt: nil)
        XCTAssertNil(summary.coverageRatio)
        XCTAssertEqual(summary.recordedDuration, 0, accuracy: 1e-9)
    }
}
