import Foundation
import XCTest
@testable import ProjectZD8

/// 区切った走行ルートから、時刻を揃えた位置の時間の軸を作る規則を検証します(設計書 §2.1 標高の垂直精度、§3.4)。
@MainActor
final class RouteAnalysisTimelineBuilderTests: XCTestCase {
    /// 既定(垂直精度の上限 15 m)の検証対象です。
    private let builder = RouteAnalysisTimelineBuilder()

    /// 走行ルートの1点を作ります。
    ///
    /// 責務: 実時間の秒・単調時刻の秒・標高・垂直精度・東向きの位置を指定した点を返します。
    /// - Parameters:
    ///   - sequence: 連番。
    ///   - wall: observedAt の基準からの秒。
    ///   - monotonic: 単調時刻の秒(0 以上の整数)。
    ///   - altitude: 標高。
    ///   - vertical: 垂直精度。
    ///   - x: 東向きの距離(m)。
    /// - Returns: 点。
    private func point(
        _ sequence: Int64,
        wall: TimeInterval,
        monotonic: UInt64,
        altitude: Double? = nil,
        vertical: Double? = nil,
        x: Double = 0
    ) -> DrivingRoutePoint {
        DrivingRoutePoint(
            sequence: sequence,
            coordinate: DrivingRouteTrackFixtures.coordinates.point(x: x, y: 0),
            observedAt: DrivingRouteTrackFixtures.date(wall),
            monotonicNanoseconds: monotonic * 1_000_000_000,
            horizontalAccuracyMeters: 5,
            altitudeMeters: altitude,
            verticalAccuracyMeters: vertical
        )
    }

    /// 1区間のルートを作ります。
    ///
    /// 責務: 点をそのまま持つ正確な区間1つのルートを返します。
    /// - Parameter points: 点。
    /// - Returns: ルート。
    private func route(_ points: [DrivingRoutePoint]) -> DrivingRoute {
        DrivingRoutePointFixtures.route([DrivingRoutePointFixtures.segment(points)])
    }

    /// 責務: 時刻の印が、ルートの点の順に observedAt と単調時刻を写したものになることを確かめます。
    func testClockStampsFollowRoutePoints() {
        let first = [point(0, wall: 0, monotonic: 100), point(1, wall: 1, monotonic: 101)]
        let second = [point(5, wall: 30, monotonic: 130)]
        let route = DrivingRoutePointFixtures.route([DrivingRoutePointFixtures.segment(first), DrivingRoutePointFixtures.segment(second)])

        let stamps = builder.clockStamps(of: route)

        let expected: [TelemetryClockStamp] = (first + second).map {
            TelemetryClockStamp(observedAt: $0.observedAt, monotonicNanoseconds: $0.monotonicNanoseconds)
        }
        XCTAssertEqual(stamps, expected)
    }

    /// 責務: 空のルートからは、空の時刻の印と空の時間の軸ができることを確かめます。
    func testEmptyRouteGivesEmptyResults() {
        let empty = DrivingRoutePointFixtures.route([])

        XCTAssertEqual(builder.clockStamps(of: empty), [])
        XCTAssertEqual(builder.timeline(route: empty, alignment: .wallClock).points, [])
    }

    /// 責務: 区間の番号と精度の段階が、点の属する区間から付くことを確かめます。
    func testSegmentIndexAndPrecisionComeFromSegment() {
        let route = DrivingRoutePointFixtures.route([
            DrivingRoutePointFixtures.segment([point(0, wall: 0, monotonic: 0), point(1, wall: 1, monotonic: 1)]),
            DrivingRoutePointFixtures.segment([point(2, wall: 40, monotonic: 40)], precision: .approximate)
        ])

        let points = builder.timeline(route: route, alignment: .wallClock).points

        XCTAssertEqual(points.map(\.segmentIndex), [0, 0, 1])
        XCTAssertEqual(points.map(\.precision), [.precise, .precise, .approximate])
    }

    /// 責務: 時刻が昇順のルートで、位置の番号・連番・座標がルートの点の順に写ることを確かめます。
    func testIndexSequenceAndCoordinateAreCopied() {
        let source = [point(7, wall: 0, monotonic: 0, x: 0), point(8, wall: 1, monotonic: 1, x: 10), point(9, wall: 2, monotonic: 2, x: 20)]

        let points = builder.timeline(route: route(source), alignment: .wallClock).points

        XCTAssertEqual(points.map(\.index), [0, 1, 2])
        XCTAssertEqual(points.map(\.sequence), [7, 8, 9])
        XCTAssertEqual(points.map(\.coordinate), source.map(\.coordinate))
    }

    /// 責務: 実時間の時計では、点の日時が observedAt になることを確かめます。
    func testWallClockDatesAreObservedAt() {
        let source = [point(0, wall: 0, monotonic: 500), point(1, wall: 3, monotonic: 900)]

        let timeline = builder.timeline(route: route(source), alignment: .wallClock)

        XCTAssertEqual(timeline.points.map(\.date), source.map(\.observedAt))
        XCTAssertEqual(timeline.alignment, .wallClock)
    }

    /// 責務: 単調時計では、点の日時が「単調秒 + オフセット」(参照日からの秒)になり、時計が軸に残ることを確かめます。
    func testMonotonicDatesUseOffset() {
        let source = [point(0, wall: 0, monotonic: 5), point(1, wall: 1, monotonic: 8)]
        let alignment = TelemetryTimeAlignment.monotonic(referenceOffsetSeconds: 1_000)

        let timeline = builder.timeline(route: route(source), alignment: alignment)

        XCTAssertEqual(timeline.points.map(\.date), [Date(timeIntervalSinceReferenceDate: 1_005), Date(timeIntervalSinceReferenceDate: 1_008)])
        XCTAssertEqual(timeline.alignment, alignment)
    }

    /// 責務: 揃えた日時がルートの順と食い違う時、点が日時の昇順に並び替わることを確かめます。
    func testPointsAreSortedByAlignedDate() {
        let route = DrivingRoutePointFixtures.route([
            DrivingRoutePointFixtures.segment([point(0, wall: 0, monotonic: 50), point(1, wall: 1, monotonic: 51)]),
            DrivingRoutePointFixtures.segment([point(2, wall: 40, monotonic: 10)])
        ])

        let points = builder.timeline(route: route, alignment: .monotonic(referenceOffsetSeconds: 0)).points

        XCTAssertEqual(points.map(\.sequence), [2, 0, 1])
        XCTAssertEqual(points.map(\.index), [2, 0, 1])
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
    }

    /// 責務: 同じ日時の点は、連番の順ではなくルートの順を保つ(安定な並び)ことを確かめます。
    func testEqualDatesKeepRouteOrder() {
        let source = [point(5, wall: 5, monotonic: 5), point(4, wall: 5, monotonic: 6), point(0, wall: 0, monotonic: 7)]

        let points = builder.timeline(route: route(source), alignment: .wallClock).points

        XCTAssertEqual(points.map(\.sequence), [0, 5, 4])
        XCTAssertEqual(points.map(\.index), [2, 0, 1])
    }

    /// 責務: 垂直精度が上限ちょうど(15.0 m)と少し内側(14.9 m)の点は標高を残すことを確かめます。
    func testAltitudeKeptWithinVerticalLimit() {
        let source = [point(0, wall: 0, monotonic: 0, altitude: 12, vertical: 15.0), point(1, wall: 1, monotonic: 1, altitude: 13, vertical: 14.9)]

        let points = builder.timeline(route: route(source), alignment: .wallClock).points

        XCTAssertEqual(points.map(\.altitudeMeters), [12, 13])
    }

    /// 責務: 垂直精度が上限の少し外側(15.01 m)の点は標高を `nil` にすることを確かめます。
    func testAltitudeDroppedBeyondVerticalLimit() {
        let source = [point(0, wall: 0, monotonic: 0, altitude: 12, vertical: 15.01)]

        let points = builder.timeline(route: route(source), alignment: .wallClock).points

        XCTAssertEqual(points.map(\.altitudeMeters), [nil])
    }

    /// 責務: 垂直精度が無い点は、標高があっても標高を `nil` にすることを確かめます。
    func testAltitudeDroppedWithoutVerticalAccuracy() {
        let source = [point(0, wall: 0, monotonic: 0, altitude: 12, vertical: nil)]

        let points = builder.timeline(route: route(source), alignment: .wallClock).points

        XCTAssertEqual(points.map(\.altitudeMeters), [nil])
    }

    /// 責務: 標高が無い点は、垂直精度が良くても標高が `nil` のままであることを確かめます。
    func testMissingAltitudeStaysNil() {
        let source = [point(0, wall: 0, monotonic: 0, altitude: nil, vertical: 3)]

        let points = builder.timeline(route: route(source), alignment: .wallClock).points

        XCTAssertEqual(points.map(\.altitudeMeters), [nil])
    }

    /// 責務: 初期化で渡した垂直精度の上限(5 m)が、内側(4.9 m)と外側(5.1 m)の判定に使われることを確かめます。
    func testCustomVerticalLimitIsApplied() {
        let strict = RouteAnalysisTimelineBuilder(maximumVerticalAccuracyMeters: 5)
        let source = [point(0, wall: 0, monotonic: 0, altitude: 12, vertical: 4.9), point(1, wall: 1, monotonic: 1, altitude: 13, vertical: 5.1)]

        let points = strict.timeline(route: route(source), alignment: .wallClock).points

        XCTAssertEqual(points.map(\.altitudeMeters), [12, nil])
    }

    /// 責務: 垂直精度が負(無効)の点は、標高を `nil` にすることを確かめます。
    func testNegativeVerticalAccuracyDropsAltitude() {
        let source = [point(0, wall: 0, monotonic: 0, altitude: 12, vertical: -1)]

        let points = builder.timeline(route: route(source), alignment: .wallClock).points

        XCTAssertEqual(points.map(\.altitudeMeters), [nil])
    }

    /// 責務: 標高が有限でない点は、垂直精度が良くても標高を `nil` にすることを確かめます。
    func testNonFiniteAltitudeIsDropped() {
        let source = [point(0, wall: 0, monotonic: 0, altitude: .nan, vertical: 3), point(1, wall: 1, monotonic: 1, altitude: .infinity, vertical: 3)]

        let points = builder.timeline(route: route(source), alignment: .wallClock).points

        XCTAssertEqual(points.map(\.altitudeMeters), [nil, nil])
    }
}
