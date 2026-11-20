import XCTest
@testable import ProjectZD8

/// `GeoPolygonCalculator` の内外判定(偶奇)と境界までの距離を、メートル単位で作った形状で検証します。
final class GeoPolygonCalculatorTests: XCTestCase {
    private let calculator = GeoPolygonCalculator()
    private let geo = GeoTestCoordinates()
    private let tolerance = 0.01

    /// 責務: 中心が原点の100 m 四方(開いた輪。始点を繰り返さない)を返します。
    private var openSquare: [GeoCoordinate] {
        geo.points([(-50, -50), (50, -50), (50, 50), (-50, 50)])
    }

    /// 責務: 同じ四角形を始点を繰り返して閉じた輪にして返します。
    private var closedSquare: [GeoCoordinate] {
        openSquare + [openSquare[0]]
    }

    /// 責務: 頂点が (±50,0)・(0,±50) の菱形(開いた輪)を返します。
    private var diamond: [GeoCoordinate] {
        geo.points([(-50, 0), (0, -50), (50, 0), (0, 50)])
    }

    /// 責務: L字(凹)の多角形を返します。外形 100×100 から右上の 50×50 を欠いた形です。
    private var lShapedRing: [GeoCoordinate] {
        geo.points([(0, 0), (100, 0), (100, 50), (50, 50), (50, 100), (0, 100)])
    }

    // MARK: contains

    /// 責務: 中心が内側、10 m 外の点が外側と判定されることを、開いた輪・閉じた輪の両方で確かめます。
    func testContainsForOpenAndClosedRing() {
        for ring in [openSquare, closedSquare] {
            XCTAssertTrue(calculator.contains(geo.point(x: 0, y: 0), ring: ring))
            XCTAssertFalse(calculator.contains(geo.point(x: 60, y: 0), ring: ring))
        }
    }

    /// 責务: 四方向の外側の点がすべて外側と判定されることを確かめます。
    func testContainsReturnsFalseOutsideInAllDirections() {
        for offset in [(60.0, 0.0), (-60.0, 0.0), (0.0, 60.0), (0.0, -60.0), (60.0, 60.0)] {
            XCTAssertFalse(calculator.contains(geo.point(x: offset.0, y: offset.1), ring: openSquare))
        }
    }

    /// 責務: 辺の近くの内側 (49,49) が内側、辺のすぐ外 (51,0) が外側であることを確かめます。
    func testContainsNearEdges() {
        XCTAssertTrue(calculator.contains(geo.point(x: 49, y: 49), ring: openSquare))
        XCTAssertTrue(calculator.contains(geo.point(x: -49, y: -49), ring: openSquare))
        XCTAssertFalse(calculator.contains(geo.point(x: 51, y: 0), ring: openSquare))
    }

    /// 責務: 凹んだ形で、欠けた部分の点が外側、残った腕の点が内側になることを確かめます。
    func testContainsHandlesConcaveShape() {
        XCTAssertTrue(calculator.contains(geo.point(x: 75, y: 25), ring: lShapedRing))
        XCTAssertTrue(calculator.contains(geo.point(x: 25, y: 75), ring: lShapedRing))
        XCTAssertFalse(calculator.contains(geo.point(x: 75, y: 75), ring: lShapedRing))
    }

    /// 責務: 頂点と同じ高さの点でも偶奇判定が崩れないことを確かめます(菱形の中心 (10,0) は内側、(-60,0) と (60,0) は外側)。
    func testContainsWhenRayPassesThroughVertices() {
        XCTAssertTrue(calculator.contains(geo.point(x: 10, y: 0), ring: diamond))
        XCTAssertFalse(calculator.contains(geo.point(x: -60, y: 0), ring: diamond))
        XCTAssertFalse(calculator.contains(geo.point(x: 60, y: 0), ring: diamond))
    }

    /// 責務: 3点未満の輪(0点・1点・2点)では、どの点も内側にならないことを確かめます。
    func testContainsReturnsFalseForFewerThanThreePoints() {
        let center = geo.point(x: 0, y: 0)
        XCTAssertFalse(calculator.contains(center, ring: []))
        XCTAssertFalse(calculator.contains(center, ring: [geo.point(x: 0, y: 0)]))
        XCTAssertFalse(calculator.contains(center, ring: geo.points([(-50, 0), (50, 0)])))
    }

    // MARK: distanceToBoundaryMeters

    /// 責務: 100 m 四方の中心から境界までが 50 m であることを、開いた輪・閉じた輪の両方で確かめます。
    func testDistanceToBoundaryFromCenter() throws {
        for ring in [openSquare, closedSquare] {
            let distance = try XCTUnwrap(calculator.distanceToBoundaryMeters(geo.point(x: 0, y: 0), ring: ring))
            XCTAssertEqual(distance, 50, accuracy: tolerance)
        }
    }

    /// 責務: 10 m 外の点の境界までの距離が 10 m であることを、開いた輪・閉じた輪の両方で確かめます。
    func testDistanceToBoundaryFromOutsidePoint() throws {
        for ring in [openSquare, closedSquare] {
            let distance = try XCTUnwrap(calculator.distanceToBoundaryMeters(geo.point(x: 60, y: 0), ring: ring))
            XCTAssertEqual(distance, 10, accuracy: tolerance)
        }
    }

    /// 責務: 開いた輪の閉じる辺(最後の点→最初の点)も境界として数えることを確かめます。
    /// 点 (-60,0) から最後の辺 (-50,50)→(-50,-50) までは 10 m。
    func testDistanceToBoundaryIncludesClosingEdgeOfOpenRing() throws {
        let distance = try XCTUnwrap(calculator.distanceToBoundaryMeters(geo.point(x: -60, y: 0), ring: openSquare))
        XCTAssertEqual(distance, 10, accuracy: tolerance)
    }

    /// 責務: 角の外側の点 (60,60) が頂点 (50,50) までの距離 √200 = 14.142 m になることを確かめます。
    func testDistanceToBoundaryFromOutsideCorner() throws {
        let distance = try XCTUnwrap(calculator.distanceToBoundaryMeters(geo.point(x: 60, y: 60), ring: openSquare))
        XCTAssertEqual(distance, 14.142, accuracy: tolerance)
    }

    /// 責務: 境界上の点の距離が 0、辺の近くの内側の点がその辺までの距離になることを確かめます。
    func testDistanceToBoundaryOnAndNearEdge() throws {
        let onEdge = try XCTUnwrap(calculator.distanceToBoundaryMeters(geo.point(x: 50, y: 20), ring: openSquare))
        XCTAssertEqual(onEdge, 0, accuracy: tolerance)
        let nearEdge = try XCTUnwrap(calculator.distanceToBoundaryMeters(geo.point(x: 45, y: 0), ring: openSquare))
        XCTAssertEqual(nearEdge, 5, accuracy: tolerance)
    }

    /// 責務: 輪が空なら `nil` になることを確かめます。
    func testDistanceToBoundaryReturnsNilForEmptyRing() {
        XCTAssertNil(calculator.distanceToBoundaryMeters(geo.point(x: 0, y: 0), ring: []))
    }
}
