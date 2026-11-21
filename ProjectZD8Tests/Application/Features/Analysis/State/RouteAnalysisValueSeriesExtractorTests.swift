import Foundation
import XCTest
@testable import ProjectZD8

/// 解析の PID の時系列から、時刻の印と、1つの PID の値の列を取り出す規則を検証します(設計書 §3.4)。
@MainActor
final class RouteAnalysisValueSeriesExtractorTests: XCTestCase {
    private typealias Samples = RouteAnalysisTimelineSampleFixtures

    /// 検証対象です。
    private let extractor = RouteAnalysisValueSeriesExtractor()
    /// 車速の PID です。
    private let speed = RouteAnalysisColorMetric.vehicleSpeed.pid

    /// 基準から `seconds` 秒後の日時を返します。
    ///
    /// 責務: テストの時刻を基準からの秒で表せるようにします。
    /// - Parameter seconds: 基準からの秒。
    /// - Returns: 日時。
    private func date(_ seconds: TimeInterval) -> Date {
        RouteAnalysisTimelinePointFixtures.base.addingTimeInterval(seconds)
    }

    /// 車速のサンプルを作ります。
    ///
    /// 責務: 連番・基準からの秒・値・単位を指定した車速(0x01/0x0D)のサンプルを返します。
    /// - Parameters:
    ///   - sequence: 連番。
    ///   - seconds: 基準からの秒。
    ///   - value: 値。
    ///   - unit: 単位。
    /// - Returns: サンプル。
    private func speedSample(_ sequence: Int64, at seconds: TimeInterval, value: Double?, unit: String? = "km/h") -> SessionLogAnalysisState.TimelineSample {
        Samples.sample(sequence: sequence, observedAt: date(seconds), value: value, unit: unit)
    }

    /// 責務: 時刻の印が、値の有無や PID を問わず、各サンプルの observedAt と単調時刻をサンプルの順に写したものになることを確かめます。
    func testClockStampsMapEverySample() {
        let timeline = [
            Samples.sample(sequence: 0, observedAt: date(0), value: 10, monotonicNanoseconds: Samples.nanoseconds(3)),
            Samples.sample(sequence: 1, observedAt: date(1), pid: 0x0C, value: 900, unit: "rpm", monotonicNanoseconds: nil),
            Samples.sample(sequence: 2, observedAt: date(2), value: nil, monotonicNanoseconds: Samples.nanoseconds(5))
        ]

        let stamps = extractor.clockStamps(in: timeline)

        XCTAssertEqual(stamps, [
            TelemetryClockStamp(observedAt: date(0), monotonicNanoseconds: Samples.nanoseconds(3)),
            TelemetryClockStamp(observedAt: date(1), monotonicNanoseconds: nil),
            TelemetryClockStamp(observedAt: date(2), monotonicNanoseconds: Samples.nanoseconds(5))
        ])
    }

    /// 責務: 空の時系列からは空の時刻の印ができることを確かめます。
    func testClockStampsOfEmptyTimelineAreEmpty() {
        XCTAssertEqual(extractor.clockStamps(in: []), [])
    }

    /// 責務: Service と PID の両方が一致するサンプルだけを取り出し、列の PID が求めた PID になることを確かめます。
    func testSeriesKeepsOnlyMatchingServiceAndPID() {
        let timeline = [
            speedSample(0, at: 0, value: 10),
            Samples.sample(sequence: 1, observedAt: date(1), service: 0x02, pid: 0x0D, value: 20),
            Samples.sample(sequence: 2, observedAt: date(2), pid: 0x0C, value: 30),
            speedSample(3, at: 3, value: 40)
        ]

        let series = extractor.series(for: speed, in: timeline, alignment: .wallClock)

        XCTAssertEqual(series.pid, speed)
        XCTAssertEqual(series.samples, [RouteAnalysisValueSample(date: date(0), value: 10), RouteAnalysisValueSample(date: date(3), value: 40)])
    }

    /// 責務: 値が `nil`・NaN・+∞・−∞ のサンプルを除くことを確かめます。
    func testSeriesDropsMissingAndNonFiniteValues() {
        let timeline = [
            speedSample(0, at: 0, value: nil),
            speedSample(1, at: 1, value: .nan),
            speedSample(2, at: 2, value: .infinity),
            speedSample(3, at: 3, value: -.infinity),
            speedSample(4, at: 4, value: 55)
        ]

        let series = extractor.series(for: speed, in: timeline, alignment: .wallClock)

        XCTAssertEqual(series.samples, [RouteAnalysisValueSample(date: date(4), value: 55)])
    }

    /// 責務: サンプルの並びが時刻の昇順でない時、日時の昇順に並べることを確かめます。
    func testSeriesIsSortedByDate() {
        let timeline = [speedSample(0, at: 9, value: 1), speedSample(1, at: 2, value: 2), speedSample(2, at: 5, value: 3)]

        let series = extractor.series(for: speed, in: timeline, alignment: .wallClock)

        XCTAssertEqual(series.samples.map(\.value), [2, 3, 1])
    }

    /// 責務: 同じ時刻のサンプルは、並びの順ではなく連番(sequence)の順になることを確かめます。
    func testSameDateIsOrderedBySequence() {
        let timeline = [speedSample(7, at: 4, value: 70), speedSample(3, at: 4, value: 30), speedSample(1, at: 0, value: 10)]

        let series = extractor.series(for: speed, in: timeline, alignment: .wallClock)

        XCTAssertEqual(series.samples.map(\.value), [10, 30, 70])
    }

    /// 責務: 単調時計では、値の日時が「単調秒 + オフセット」になることを確かめます。
    func testSeriesUsesAlignmentForDates() {
        let timeline = [Samples.sample(sequence: 0, observedAt: date(0), value: 12, monotonicNanoseconds: Samples.nanoseconds(40))]

        let series = extractor.series(for: speed, in: timeline, alignment: .monotonic(referenceOffsetSeconds: 2_000))

        XCTAssertEqual(series.samples, [RouteAnalysisValueSample(date: Date(timeIntervalSinceReferenceDate: 2_040), value: 12)])
    }

    /// 責務: 列の単位が、最初の `nil` でない単位になることを確かめます。
    func testUnitIsFirstNonNilUnit() {
        let timeline = [speedSample(0, at: 0, value: 1, unit: nil), speedSample(1, at: 1, value: 2, unit: "km/h"), speedSample(2, at: 2, value: 3, unit: "mph")]

        let series = extractor.series(for: speed, in: timeline, alignment: .wallClock)

        XCTAssertEqual(series.unit, "km/h")
    }

    /// 責務: 一致するサンプルの単位がすべて `nil` なら、列の単位も `nil` になることを確かめます。
    func testUnitIsNilWhenNoSampleHasUnit() {
        let timeline = [speedSample(0, at: 0, value: 1, unit: nil)]

        XCTAssertNil(extractor.series(for: speed, in: timeline, alignment: .wallClock).unit)
    }

    /// 責務: 一致するサンプルが無ければ、求めた PID の空の列になることを確かめます。
    func testMissingPIDGivesEmptySeries() {
        let timeline = [Samples.sample(sequence: 0, observedAt: date(0), pid: 0x0C, value: 800, unit: "rpm")]

        let series = extractor.series(for: speed, in: timeline, alignment: .wallClock)

        XCTAssertEqual(series.pid, speed)
        XCTAssertTrue(series.isEmpty)
        XCTAssertNil(series.unit)
    }

    /// 責務: 単位は、絞って日時の順に並べた後で最初の `nil` でない単位になり、他の PID の単位を使わないことを確かめます。
    func testUnitFollowsSortedOrder() {
        let timeline = [
            Samples.sample(sequence: 0, observedAt: date(0), pid: 0x0C, value: 800, unit: "rpm"),
            speedSample(1, at: 5, value: 2, unit: "mph"),
            speedSample(2, at: 1, value: 1, unit: "km/h")
        ]

        XCTAssertEqual(extractor.series(for: speed, in: timeline, alignment: .wallClock).unit, "km/h")
    }
}
