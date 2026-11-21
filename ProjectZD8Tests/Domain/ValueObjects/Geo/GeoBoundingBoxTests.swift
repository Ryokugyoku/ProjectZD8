import XCTest
@testable import ProjectZD8

/// `GeoBoundingBox` の初期化の成功と失敗の境界、包含・合成・拡張を検証します。
final class GeoBoundingBoxTests: XCTestCase {
    /// 責務: 座標を作ります。作れなければテストを止めます。
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> GeoCoordinate {
        try XCTUnwrap(GeoCoordinate(latitude: latitude, longitude: longitude))
    }

    /// 責務: 範囲を作ります。作れなければテストを止めます。
    private func box(_ minLat: Double, _ maxLat: Double, _ minLon: Double, _ maxLon: Double) throws -> GeoBoundingBox {
        try XCTUnwrap(GeoBoundingBox(minLatitude: minLat, maxLatitude: maxLat, minLongitude: minLon, maxLongitude: maxLon))
    }

    /// 責務: min = max(1点だけの範囲)と全球が成功することを確かめます。
    func testDegenerateAndWholeGlobeAreValid() {
        XCTAssertNotNil(GeoBoundingBox(minLatitude: 10, maxLatitude: 10, minLongitude: 20, maxLongitude: 20))
        XCTAssertNotNil(GeoBoundingBox(minLatitude: -90, maxLatitude: 90, minLongitude: -180, maxLongitude: 180))
    }

    /// 責務: min が max より大きい、または値が座標として無効な場合に失敗することを確かめます。
    func testInvalidRangesFail() {
        XCTAssertNil(GeoBoundingBox(minLatitude: 11, maxLatitude: 10, minLongitude: 0, maxLongitude: 1))
        XCTAssertNil(GeoBoundingBox(minLatitude: 0, maxLatitude: 1, minLongitude: 21, maxLongitude: 20))
        XCTAssertNil(GeoBoundingBox(minLatitude: -91, maxLatitude: 0, minLongitude: 0, maxLongitude: 1))
        XCTAssertNil(GeoBoundingBox(minLatitude: 0, maxLatitude: 91, minLongitude: 0, maxLongitude: 1))
        XCTAssertNil(GeoBoundingBox(minLatitude: 0, maxLatitude: 1, minLongitude: -181, maxLongitude: 0))
        XCTAssertNil(GeoBoundingBox(minLatitude: 0, maxLatitude: 1, minLongitude: 0, maxLongitude: 181))
        XCTAssertNil(GeoBoundingBox(minLatitude: .nan, maxLatitude: 1, minLongitude: 0, maxLongitude: 1))
        XCTAssertNil(GeoBoundingBox(minLatitude: 0, maxLatitude: .infinity, minLongitude: 0, maxLongitude: 1))
    }

    /// 責務: 座標の列を囲む範囲が最小・最大を取ることと、空の列で失敗することを確かめます。
    func testEnclosingCoordinates() throws {
        XCTAssertNil(GeoBoundingBox(enclosing: []))
        let points = [try coordinate(26.0, 127.5), try coordinate(26.5, 127.0), try coordinate(26.2, 128.0)]
        let enclosing = try XCTUnwrap(GeoBoundingBox(enclosing: points))
        XCTAssertEqual(enclosing, try box(26.0, 26.5, 127.0, 128.0))
        let single = try XCTUnwrap(GeoBoundingBox(enclosing: [points[0]]))
        XCTAssertEqual(single, try box(26.0, 26.0, 127.5, 127.5))
    }

    /// 責務: 包含判定が境界を含み、外側を含まないことを確かめます。
    func testContainsIncludesBoundary() throws {
        let area = try box(10, 20, 30, 40)
        XCTAssertTrue(area.contains(try coordinate(10, 30)))
        XCTAssertTrue(area.contains(try coordinate(20, 40)))
        XCTAssertTrue(area.contains(try coordinate(15, 35)))
        XCTAssertFalse(area.contains(try coordinate(9.999, 35)))
        XCTAssertFalse(area.contains(try coordinate(15, 40.001)))
    }

    /// 責務: union が両方を覆う最小の範囲になることを確かめます。
    func testUnion() throws {
        let merged = try box(0, 10, 0, 10).union(try box(5, 20, -5, 3))
        XCTAssertEqual(merged, try box(0, 20, -5, 10))
    }

    /// 責務: 拡張が緯度方向に m ÷ 111,195.08 度、経度方向に cos 補正した度数だけ広げることを確かめます。
    func testExpandedByMeters() throws {
        let expanded = try box(0, 0, 100, 100).expanded(byMeters: 1_000)
        let delta = 1_000 / 111_195.08
        XCTAssertEqual(expanded.minLatitude, -delta, accuracy: 1e-9)
        XCTAssertEqual(expanded.maxLatitude, delta, accuracy: 1e-9)
        XCTAssertEqual(expanded.minLongitude, 100 - delta, accuracy: 1e-9)
        XCTAssertEqual(expanded.maxLongitude, 100 + delta, accuracy: 1e-9)
        let north = try box(60, 60, 0, 0).expanded(byMeters: 1_000)
        XCTAssertEqual(north.maxLongitude, delta / 0.5, accuracy: 1e-7)
    }

    /// 責務: 負・NaN・無限大の距離は 0 とみなされ、範囲が変わらないことを確かめます。
    func testExpandedWithInvalidDistanceKeepsBox() throws {
        let original = try box(10, 20, 30, 40)
        XCTAssertEqual(original.expanded(byMeters: -500), original)
        XCTAssertEqual(original.expanded(byMeters: .nan), original)
        XCTAssertEqual(original.expanded(byMeters: .infinity), original)
        XCTAssertEqual(original.expanded(byMeters: 0), original)
    }

    /// 責務: 拡張が ±90・±180 で切り詰められ、極付近で経度が全範囲になることを確かめます。
    func testExpandedClampsAndCoversAllLongitudeNearPole() throws {
        let nearEdge = try box(89.9999, 90, 179.9999, 180).expanded(byMeters: 1_000_000)
        XCTAssertEqual(nearEdge.maxLatitude, 90)
        XCTAssertEqual(nearEdge.maxLongitude, 180)
        let pole = try box(90, 90, 10, 10).expanded(byMeters: 100)
        XCTAssertEqual(pole.minLongitude, -180)
        XCTAssertEqual(pole.maxLongitude, 180)
        let south = try box(-90, -90, 0, 0).expanded(byMeters: 100)
        XCTAssertEqual(south.minLatitude, -90)
        XCTAssertEqual(south.minLongitude, -180)
    }

    /// 責務: 定数 metersPerDegree が 111,195.08 であることを確かめます。
    func testMetersPerDegreeConstant() {
        XCTAssertEqual(GeoBoundingBox.metersPerDegree, 111_195.08)
    }
}
