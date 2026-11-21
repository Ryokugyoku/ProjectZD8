import XCTest
@testable import ProjectZD8

/// `TelemetryTimeAlignment.date(for:)` を、設計書 §3.1 の式から独立に計算した値で検証します。
@MainActor
final class TelemetryTimeAlignmentTests: XCTestCase {
    private let observedAt = Date(timeIntervalSinceReferenceDate: 700_000_000)

    /// 責務: 実時間では単調時刻の有無にかかわらず observedAt を返すことを確かめます。
    func testWallClockReturnsObservedAt() {
        let withMonotonic = TelemetryClockStamp(observedAt: observedAt, monotonicNanoseconds: 5_000_000_000)
        let withoutMonotonic = TelemetryClockStamp(observedAt: observedAt, monotonicNanoseconds: nil)
        XCTAssertEqual(TelemetryTimeAlignment.wallClock.date(for: withMonotonic), observedAt)
        XCTAssertEqual(TelemetryTimeAlignment.wallClock.date(for: withoutMonotonic), observedAt)
    }

    /// 責務: 単調時計では、参照日からの秒 = 単調秒 + オフセットになることを確かめます(5 s + 700,000,000 s)。
    func testMonotonicAddsOffsetToMonotonicSeconds() {
        let stamp = TelemetryClockStamp(observedAt: observedAt, monotonicNanoseconds: 5_000_000_000)
        let result = TelemetryTimeAlignment.monotonic(referenceOffsetSeconds: 700_000_000).date(for: stamp)
        XCTAssertEqual(result, Date(timeIntervalSinceReferenceDate: 700_000_005))
    }

    /// 責務: 単調時計の時、observedAt が結果に影響しない(単調時刻とオフセットだけで決まる)ことを確かめます。
    func testMonotonicIgnoresObservedAt() {
        let alignment = TelemetryTimeAlignment.monotonic(referenceOffsetSeconds: 100)
        let early = TelemetryClockStamp(observedAt: Date(timeIntervalSinceReferenceDate: 0), monotonicNanoseconds: 2_000_000_000)
        let late = TelemetryClockStamp(observedAt: Date(timeIntervalSinceReferenceDate: 999), monotonicNanoseconds: 2_000_000_000)
        XCTAssertEqual(alignment.date(for: early), Date(timeIntervalSinceReferenceDate: 102))
        XCTAssertEqual(alignment.date(for: late), Date(timeIntervalSinceReferenceDate: 102))
    }

    /// 責務: 単調時計でも単調時刻が nil なら observedAt を返すことを確かめます。
    func testMonotonicWithoutMonotonicStampFallsBackToObservedAt() {
        let stamp = TelemetryClockStamp(observedAt: observedAt, monotonicNanoseconds: nil)
        XCTAssertEqual(TelemetryTimeAlignment.monotonic(referenceOffsetSeconds: 123).date(for: stamp), observedAt)
    }

    /// 責務: 負のオフセットと 0 ナノ秒でも式どおり(0 + オフセット)になることを確かめます。
    func testMonotonicWithNegativeOffsetAndZeroNanoseconds() {
        let stamp = TelemetryClockStamp(observedAt: observedAt, monotonicNanoseconds: 0)
        let result = TelemetryTimeAlignment.monotonic(referenceOffsetSeconds: -40).date(for: stamp)
        XCTAssertEqual(result, Date(timeIntervalSinceReferenceDate: -40))
    }

    /// 責務: 1.5 秒(1,500,000,000 ns)のような小数秒が、秒へ正しく直ることを確かめます。
    func testMonotonicFractionalSeconds() {
        let stamp = TelemetryClockStamp(observedAt: observedAt, monotonicNanoseconds: 1_500_000_000)
        let result = TelemetryTimeAlignment.monotonic(referenceOffsetSeconds: 10).date(for: stamp)
        XCTAssertEqual(result.timeIntervalSinceReferenceDate, 11.5, accuracy: 1e-9)
    }

    /// 責務: 同じ単調時刻の2件が、同じ時刻になることを確かめます(位置と PID の対応の前提)。
    func testSameMonotonicStampGivesSameDate() {
        let alignment = TelemetryTimeAlignment.monotonic(referenceOffsetSeconds: 50)
        let a = TelemetryClockStamp(observedAt: observedAt, monotonicNanoseconds: 9_000_000_000)
        let b = TelemetryClockStamp(observedAt: observedAt.addingTimeInterval(3), monotonicNanoseconds: 9_000_000_000)
        XCTAssertEqual(alignment.date(for: a), alignment.date(for: b))
    }
}
