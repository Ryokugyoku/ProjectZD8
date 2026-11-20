import XCTest
@testable import ProjectZD8

/// `GeoCoordinate` の初期化の成功と失敗の境界を検証します。
final class GeoCoordinateTests: XCTestCase {
    /// 責務: 緯度 ±90・経度 ±180 ちょうどが成功することを確かめます。
    func testBoundaryValuesAreValid() {
        XCTAssertNotNil(GeoCoordinate(latitude: 90, longitude: 0))
        XCTAssertNotNil(GeoCoordinate(latitude: -90, longitude: 0))
        XCTAssertNotNil(GeoCoordinate(latitude: 0, longitude: 180))
        XCTAssertNotNil(GeoCoordinate(latitude: 0, longitude: -180))
        XCTAssertNotNil(GeoCoordinate(latitude: 0, longitude: 0))
    }

    /// 責務: 範囲をわずかに超えた値が失敗することを確かめます。
    func testJustOutsideRangeFails() {
        XCTAssertNil(GeoCoordinate(latitude: 90.000001, longitude: 0))
        XCTAssertNil(GeoCoordinate(latitude: -90.000001, longitude: 0))
        XCTAssertNil(GeoCoordinate(latitude: 0, longitude: 180.000001))
        XCTAssertNil(GeoCoordinate(latitude: 0, longitude: -180.000001))
    }

    /// 責務: 有限でない値(NaN・無限大)が失敗することを確かめます。
    func testNonFiniteValuesFail() {
        XCTAssertNil(GeoCoordinate(latitude: .nan, longitude: 0))
        XCTAssertNil(GeoCoordinate(latitude: 0, longitude: .nan))
        XCTAssertNil(GeoCoordinate(latitude: .infinity, longitude: 0))
        XCTAssertNil(GeoCoordinate(latitude: 0, longitude: -.infinity))
    }

    /// 責務: 値が保持され、同じ値同士が等しいことを確かめます。
    func testStoresValuesAndIsEquatable() {
        let coordinate = GeoCoordinate(latitude: 26.2, longitude: 127.7)
        XCTAssertEqual(coordinate?.latitude, 26.2)
        XCTAssertEqual(coordinate?.longitude, 127.7)
        XCTAssertEqual(coordinate, GeoCoordinate(latitude: 26.2, longitude: 127.7))
        XCTAssertNotEqual(coordinate, GeoCoordinate(latitude: 26.2, longitude: 127.8))
    }

    /// 責務: 静的な判定関数が、初期化と同じ境界で動くことを確かめます。
    func testStaticValidators() {
        XCTAssertTrue(GeoCoordinate.isValidLatitude(90))
        XCTAssertFalse(GeoCoordinate.isValidLatitude(90.5))
        XCTAssertFalse(GeoCoordinate.isValidLatitude(.nan))
        XCTAssertTrue(GeoCoordinate.isValidLongitude(-180))
        XCTAssertFalse(GeoCoordinate.isValidLongitude(181))
        XCTAssertFalse(GeoCoordinate.isValidLongitude(.infinity))
    }
}
