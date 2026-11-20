import Foundation
import XCTest
@testable import ProjectZD8

/// 区切った軌跡から地図に描く線・印・範囲を作る規則を検証します。
@MainActor
final class DrivingRouteMapContentBuilderTests: XCTestCase {
    /// 検証対象です(既定の間引きと点の上限 4,000)。
    private let builder = DrivingRouteMapContentBuilder()

    /// 描ける点が無ければ nil です。
    ///
    /// 責務: 区間の無いルートが、終了済みかによらず nil になることを確認します。
    func testEmptyRouteGivesNil() {
        let route = DrivingRouteTestValues.route([], totalFixCount: 3, excludedFixCount: 3)

        XCTAssertNil(builder.geometry(for: route, sessionHasEnded: true))
        XCTAssertNil(builder.geometry(for: route, sessionHasEnded: false))
    }

    /// 2点以上の区間ごとに1本の線になり、1点の区間は線にしません。
    ///
    /// 責務: 3点・1点・2点の区間から、1点の区間を除いた2本の線が区間の順に、点数の上限内なら座標そのままで出ることを確認します。
    func testEachSegmentWithTwoOrMorePointsBecomesOnePolyline() throws {
        let segments = try threeSegments()

        let geometry = try XCTUnwrap(builder.geometry(for: DrivingRouteTestValues.route(segments), sessionHasEnded: true))

        XCTAssertEqual(geometry.polylines.map(\.coordinates), [coordinates(of: segments[0]), coordinates(of: segments[2])])
    }

    /// 線の概略の印は、区間の精度の段階と一致します。
    ///
    /// 責務: 正確な区間は実線、概略の区間は概略(破線)として出ることを確認します。
    func testPolylineApproximationMatchesSegmentPrecision() throws {
        let geometry = try XCTUnwrap(
            builder.geometry(for: DrivingRouteTestValues.route(try threeSegments()), sessionHasEnded: true)
        )

        XCTAssertEqual(geometry.polylines.map(\.isApproximate), [false, true])
    }

    /// 範囲は、間引く前の全区間の全ての点(1点の区間も含む)の外接矩形です。
    ///
    /// 責務: 線にしない1点の区間の点も含めて全ての点が範囲に入り、範囲が全点の外接矩形と一致することを確認します。
    func testBoundsEncloseAllPointsIncludingSinglePointSegment() throws {
        let route = DrivingRouteTestValues.route(try threeSegments())

        let geometry = try XCTUnwrap(builder.geometry(for: route, sessionHasEnded: true))

        for point in route.points {
            XCTAssertTrue(geometry.bounds.contains(point.coordinate), "\(point.sequence)")
        }
        XCTAssertEqual(geometry.bounds, GeoBoundingBox(enclosing: route.points.map(\.coordinate)))
    }

    /// 間引いた時も、範囲は間引く前の全点の外接矩形です。
    ///
    /// 責務: 点の上限で間引かれるルートで、範囲が間引く前の全点の外接矩形と一致することを確認します。
    func testBoundsUsePointsBeforeSimplification() throws {
        let route = DrivingRouteTestValues.route([try DrivingRouteTestValues.segment(0..<500)])

        let geometry = try XCTUnwrap(DrivingRouteMapContentBuilder(pointBudget: 20).geometry(for: route, sessionHasEnded: true))

        XCTAssertEqual(geometry.bounds, GeoBoundingBox(enclosing: route.points.map(\.coordinate)))
    }

    /// 同じ座標へ戻る周回でも、最後の点が最初の点と別の点なら到着の印を出します。
    ///
    /// 責務: 最初と最後の座標が同じ3点の区間で、終了済みなら出発と到着の印が同じ座標に1つずつ出ることを確認します。
    func testLoopReturningToStartCoordinateStillHasEndMarker() throws {
        let latitude = DrivingRouteTestValues.baseLatitude
        let points = try [
            DrivingRouteTestValues.point(index: 0, latitude: latitude),
            DrivingRouteTestValues.point(index: 1, latitude: latitude + 0.001),
            DrivingRouteTestValues.point(index: 2, latitude: latitude),
        ]
        let route = DrivingRouteTestValues.route([DrivingRouteSegment(points: points, precision: .precise)])

        let geometry = try XCTUnwrap(builder.geometry(for: route, sessionHasEnded: true))

        XCTAssertEqual(markers(geometry, .start), [points[0].coordinate])
        XCTAssertEqual(markers(geometry, .end), [points[2].coordinate])
    }

    /// 区間が複数ある時、出発の印は最初の区間の最初の点、到着の印は最後の区間の最後の点です。
    ///
    /// 責務: 終了済みのセッションで、出発と到着の印が1つずつ正しい座標に出ることを確認します。
    func testStartAndEndMarkersUseFirstAndLastPointsAcrossSegments() throws {
        let segments = try threeSegments()

        let geometry = try XCTUnwrap(builder.geometry(for: DrivingRouteTestValues.route(segments), sessionHasEnded: true))

        XCTAssertEqual(markers(geometry, .start), [try XCTUnwrap(segments.first?.points.first).coordinate])
        XCTAssertEqual(markers(geometry, .end), [try XCTUnwrap(segments.last?.points.last).coordinate])
    }

    /// 進行中のセッションには到着の印を出しません。
    ///
    /// 責務: `sessionHasEnded` が false の時、出発の印だけになることを確認します。
    func testNoEndMarkerWhileSessionIsInProgress() throws {
        let segments = try threeSegments()

        let geometry = try XCTUnwrap(builder.geometry(for: DrivingRouteTestValues.route(segments), sessionHasEnded: false))

        XCTAssertEqual(markers(geometry, .start), [try XCTUnwrap(segments.first?.points.first).coordinate])
        XCTAssertEqual(markers(geometry, .end), [])
    }

    /// 1点だけのルートは線にしませんが、出発の印と範囲を出し、終了済みでも到着の印は出しません。
    ///
    /// 責務: 最後の点が最初の点と同じ時に到着の印が出ないことと、範囲がその点を含むことを確認します。
    func testSinglePointRouteHasStartMarkerOnly() throws {
        let segment = try DrivingRouteTestValues.segment(0..<1)
        let point = try XCTUnwrap(segment.points.first)

        let geometry = try XCTUnwrap(builder.geometry(for: DrivingRouteTestValues.route([segment]), sessionHasEnded: true))

        XCTAssertEqual(geometry.polylines, [])
        XCTAssertEqual(markers(geometry, .start), [point.coordinate])
        XCTAssertEqual(markers(geometry, .end), [])
        XCTAssertTrue(geometry.bounds.contains(point.coordinate))
    }

    /// 線の id は2点以上の区間の順に 0 から、印の id は出発が 0、到着が 1 です。
    ///
    /// 責務: 1点の区間を挟む4区間で線の id が 0・1・2 と一意に振られ、印の id が種類ごとに固定であることを確認します。
    func testIdentifiersAreSequentialAndUnique() throws {
        let segments = try [
            DrivingRouteTestValues.segment(0..<3),
            DrivingRouteTestValues.segment(3..<4),
            DrivingRouteTestValues.segment(4..<7, precision: .approximate),
            DrivingRouteTestValues.segment(7..<10),
        ]

        let geometry = try XCTUnwrap(builder.geometry(for: DrivingRouteTestValues.route(segments), sessionHasEnded: true))

        XCTAssertEqual(geometry.polylines.map(\.id), [0, 1, 2])
        XCTAssertEqual(geometry.polylines.map(\.coordinates.first), [0, 2, 3].map { segments[$0].points.first?.coordinate })
        XCTAssertEqual(geometry.markers.first { $0.endpoint == .start }?.id, 0)
        XCTAssertEqual(geometry.markers.first { $0.endpoint == .end }?.id, 1)
        XCTAssertEqual(geometry.markers.count, 2)
    }

    /// 点の上限を超えるルートは、上限以下に間引き、各線の端点を残します。
    ///
    /// 責務: 上限 100 で 1,000 点のジグザグの区間2本を渡した時、合計が100以下で各線の最初と最後の座標が保たれることを確認します。
    func testPointBudgetIsRespectedAndEndpointsAreKept() throws {
        let segments = try [DrivingRouteTestValues.segment(0..<1_000), DrivingRouteTestValues.segment(1_000..<2_000)]
        let limited = DrivingRouteMapContentBuilder(pointBudget: 100)

        let geometry = try XCTUnwrap(limited.geometry(for: DrivingRouteTestValues.route(segments), sessionHasEnded: true))

        XCTAssertLessThanOrEqual(geometry.polylines.reduce(0) { $0 + $1.coordinates.count }, 100)
        XCTAssertEqual(geometry.polylines.map { $0.coordinates.first }, segments.map { $0.points.first?.coordinate })
        XCTAssertEqual(geometry.polylines.map { $0.coordinates.last }, segments.map { $0.points.last?.coordinate })
    }

    /// 3点の正確な区間・1点の正確な区間・2点の概略の区間を作ります。
    ///
    /// 責務: 線になる区間とならない区間、精度の異なる区間を1つのルートに並べます。
    /// - Returns: 区間の順に並べた3区間。
    /// - Throws: 値を作れない場合のテスト失敗。
    private func threeSegments() throws -> [DrivingRouteSegment] {
        try [
            DrivingRouteTestValues.segment(0..<3),
            DrivingRouteTestValues.segment(3..<4),
            DrivingRouteTestValues.segment(4..<6, precision: .approximate),
        ]
    }

    /// 区間の点の座標を返します。
    ///
    /// 責務: 線の座標と比べるため、区間の点を座標の列にします。
    /// - Parameter segment: 区間。
    /// - Returns: 座標の列。
    private func coordinates(of segment: DrivingRouteSegment) -> [GeoCoordinate] {
        segment.points.map(\.coordinate)
    }

    /// 指定した種類の印の座標を返します。
    ///
    /// 責務: 印の並び順に依存せず、種類ごとの座標を取り出します。
    /// - Parameters:
    ///   - geometry: 地図の形。
    ///   - endpoint: 印の種類。
    /// - Returns: その種類の印の座標。
    private func markers(_ geometry: DrivingRouteMapGeometry, _ endpoint: DrivingRouteEndpoint) -> [GeoCoordinate] {
        geometry.markers.filter { $0.endpoint == endpoint }.map(\.coordinate)
    }
}
