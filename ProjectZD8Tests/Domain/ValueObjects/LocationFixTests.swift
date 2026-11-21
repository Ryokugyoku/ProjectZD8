import XCTest
@testable import ProjectZD8

/// `LocationFix` の緯度経度・水平精度の不変条件と、値の保持を検証します。
final class LocationFixTests: XCTestCase {
    /// 責務: 既定で有効な位置を、指定した項目だけ差し替えて作ります。
    private func makeFix(
        latitude: Double = 35.0,
        longitude: Double = 139.0,
        horizontalAccuracy: Double = 5
    ) -> LocationFix? {
        LocationFix(
            latitude: latitude,
            longitude: longitude,
            altitudeMeters: nil,
            horizontalAccuracyMeters: horizontalAccuracy,
            verticalAccuracyMeters: nil,
            speedMetersPerSecond: nil,
            courseDegrees: nil,
            observedAt: Date(timeIntervalSince1970: 1_000),
            monotonicNanoseconds: 1
        )
    }

    /// 責務: 緯度経度の境界値(±90、±180)が有効であることを確かめます。
    func testBoundaryCoordinatesAreValid() {
        XCTAssertNotNil(makeFix(latitude: -90))
        XCTAssertNotNil(makeFix(latitude: 90))
        XCTAssertNotNil(makeFix(longitude: -180))
        XCTAssertNotNil(makeFix(longitude: 180))
    }

    /// 責務: 緯度が範囲外なら nil になることを確かめます。
    func testLatitudeOutOfRangeIsRejected() {
        XCTAssertNil(makeFix(latitude: -90.0001))
        XCTAssertNil(makeFix(latitude: 90.0001))
    }

    /// 責務: 経度が範囲外なら nil になることを確かめます。
    func testLongitudeOutOfRangeIsRejected() {
        XCTAssertNil(makeFix(longitude: -180.0001))
        XCTAssertNil(makeFix(longitude: 180.0001))
    }

    /// 責務: 緯度・経度が NaN や無限大なら nil になることを確かめます。
    func testNonFiniteCoordinatesAreRejected() {
        XCTAssertNil(makeFix(latitude: .nan))
        XCTAssertNil(makeFix(longitude: .nan))
        XCTAssertNil(makeFix(latitude: .infinity))
        XCTAssertNil(makeFix(longitude: -.infinity))
    }

    /// 責務: 水平精度 0 が有効であることを確かめます。
    func testZeroHorizontalAccuracyIsValid() {
        XCTAssertNotNil(makeFix(horizontalAccuracy: 0))
    }

    /// 責務: 水平精度が負・NaN・無限大なら nil になることを確かめます。
    func testInvalidHorizontalAccuracyIsRejected() {
        XCTAssertNil(makeFix(horizontalAccuracy: -0.001))
        XCTAssertNil(makeFix(horizontalAccuracy: .nan))
        XCTAssertNil(makeFix(horizontalAccuracy: .infinity))
    }

    /// 責務: 有効な位置が全プロパティを引数どおりに保持することを確かめます。
    func testValidFixKeepsAllProperties() throws {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let fix = try XCTUnwrap(LocationFix(
            latitude: 35.6812,
            longitude: 139.7671,
            altitudeMeters: 12.5,
            horizontalAccuracyMeters: 4.5,
            verticalAccuracyMeters: 3.5,
            speedMetersPerSecond: 16.7,
            courseDegrees: 123.4,
            observedAt: observedAt,
            monotonicNanoseconds: 987_654_321
        ))
        XCTAssertEqual(fix.latitude, 35.6812)
        XCTAssertEqual(fix.longitude, 139.7671)
        XCTAssertEqual(fix.altitudeMeters, 12.5)
        XCTAssertEqual(fix.horizontalAccuracyMeters, 4.5)
        XCTAssertEqual(fix.verticalAccuracyMeters, 3.5)
        XCTAssertEqual(fix.speedMetersPerSecond, 16.7)
        XCTAssertEqual(fix.courseDegrees, 123.4)
        XCTAssertEqual(fix.observedAt, observedAt)
        XCTAssertEqual(fix.monotonicNanoseconds, 987_654_321)
    }

    /// 責務: 任意項目がすべて nil でも有効で、nil のまま保持されることを確かめます。
    func testOptionalValuesStayNilWhenAbsent() throws {
        let fix = try XCTUnwrap(makeFix())
        XCTAssertNil(fix.altitudeMeters)
        XCTAssertNil(fix.verticalAccuracyMeters)
        XCTAssertNil(fix.speedMetersPerSecond)
        XCTAssertNil(fix.courseDegrees)
    }
}
