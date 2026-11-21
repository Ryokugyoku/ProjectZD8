import Foundation
import XCTest
@testable import ProjectZD8

/// 標高のグラフ用の点列を作る規則(標高のある点だけ、2点未満なら無し、線の切れ目 10 s、最小と最大)を検証します(設計書 §2.3、§11 R14)。
@MainActor
final class RouteAnalysisChartSeriesBuilderElevationTests: XCTestCase {
    private typealias Fixtures = RouteAnalysisRouteTimelineFixtures

    /// 検証対象です。
    private let builder = RouteAnalysisChartSeriesBuilder()

    /// 秒と標高の組から時間の軸を作ります。
    ///
    /// 責務: 1区間に 100 m おきで、指定の秒と標高の点を並べます。
    /// - Parameter samples: 秒と標高の組。
    /// - Returns: 時間の軸。
    private func timeline(_ samples: [(seconds: TimeInterval, altitude: Double?)]) -> RouteAnalysisTimeline {
        let points: [RouteAnalysisTimelinePoint] = samples.enumerated().map { offset, sample in
            Fixtures.point(
                index: offset,
                sequence: Int64(offset),
                segmentIndex: 0,
                x: Double(offset) * 100,
                seconds: sample.seconds,
                altitude: sample.altitude
            )
        }
        return Fixtures.timeline(points: points)
    }

    /// 責務: 標高のある点が 0 点・1 点なら、グラフができないことを確かめます。
    func testFewerThanTwoAltitudesGiveNil() {
        XCTAssertNil(builder.elevationSeries(timeline([(0, nil), (1, nil)])))
        XCTAssertNil(builder.elevationSeries(timeline([(0, nil), (1, 12), (2, nil)])))
        XCTAssertNil(builder.elevationSeries(timeline([])))
    }

    /// 責務: 標高のある点がちょうど 2 点ならグラフができることを確かめます。
    func testTwoAltitudesGiveSeries() throws {
        let chart = try XCTUnwrap(builder.elevationSeries(timeline([(0, 12), (1, nil), (2, 14)])))

        XCTAssertEqual(chart.points.map(\.value), [12, 14])
        XCTAssertEqual(chart.titleKey, "analysis.route.elevation.title")
        XCTAssertEqual(chart.unit, "m")
    }

    /// 責務: 標高のある点だけを、日時と標高のまま順に持ち、最小と最大が標高の最小と最大になることを確かめます。
    func testUsesOnlyPointsWithAltitude() throws {
        let source = timeline([(0, 10), (1, nil), (2, 30), (3, 20)])

        let chart = try XCTUnwrap(builder.elevationSeries(source))

        XCTAssertEqual(chart.points.map(\.value), [10, 30, 20])
        XCTAssertEqual(chart.points.map(\.date), [source.points[0].date, source.points[2].date, source.points[3].date])
        XCTAssertEqual(chart.minimum, 10)
        XCTAssertEqual(chart.maximum, 30)
        XCTAssertEqual(Set(chart.points.map(\.id)).count, 3)
    }

    /// 責務: 標高のある点の時間差が 9 s なら同じ線、11 s なら次の線になることを確かめます。
    func testElevationLineBreaksBeyondTenSeconds() throws {
        let chart = try XCTUnwrap(builder.elevationSeries(timeline([(0, 1), (9, 2), (20, 3)])))

        XCTAssertEqual(chart.points.map(\.lineID), [0, 0, 1])
    }

    /// 責務: 区間の番号が変わっても、時間差が 10 s 以内なら線を分けないことを確かめます。
    func testSegmentChangeDoesNotBreakLine() throws {
        let points = [
            RouteAnalysisRouteTimelineFixtures.point(index: 0, sequence: 0, segmentIndex: 0, x: 0, seconds: 0, altitude: 5),
            RouteAnalysisRouteTimelineFixtures.point(index: 1, sequence: 1, segmentIndex: 1, x: 100, seconds: 3, altitude: 6)
        ]

        let chart = try XCTUnwrap(builder.elevationSeries(Fixtures.timeline(points: points)))

        XCTAssertEqual(chart.points.map(\.lineID), [0, 0])
    }

    /// 責務: 標高の点が 600 点を超えれば 600 点以下に減り、最小と最大の標高の点を含むことを確かめます。
    func testLargeElevationIsReducedAndKeepsExtremes() throws {
        var samples: [(seconds: TimeInterval, altitude: Double?)] = (0..<1_500).map { (TimeInterval($0), 100 + 5 * sin(Double($0) / 9)) }
        samples[700].altitude = -3
        samples[90].altitude = 250

        let chart = try XCTUnwrap(builder.elevationSeries(timeline(samples)))

        XCTAssertLessThanOrEqual(chart.points.count, 600)
        XCTAssertTrue(chart.points.contains { $0.value == -3 })
        XCTAssertTrue(chart.points.contains { $0.value == 250 })
        XCTAssertEqual(chart.minimum, -3)
        XCTAssertEqual(chart.maximum, 250)
    }
}
