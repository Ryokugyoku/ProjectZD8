import XCTest
@testable import ProjectZD8

/// `LocationFix` の標高と垂直精度の組・速度・進行方向の不変条件を検証します。
final class LocationFixOptionalValueTests: XCTestCase {
    /// 責務: 任意項目だけを差し替えた位置を作ります。
    private func makeFix(
        altitude: Double? = nil,
        verticalAccuracy: Double? = nil,
        speed: Double? = nil,
        course: Double? = nil
    ) -> LocationFix? {
        LocationFix(
            latitude: 35.0,
            longitude: 139.0,
            altitudeMeters: altitude,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: verticalAccuracy,
            speedMetersPerSecond: speed,
            courseDegrees: course,
            observedAt: Date(timeIntervalSince1970: 1_000),
            monotonicNanoseconds: 1
        )
    }

    /// 責務: 標高と垂直精度が両方 nil、または両方値ありなら有効なことを確かめます。
    func testAltitudePairBothNilOrBothPresentIsValid() {
        XCTAssertNotNil(makeFix(altitude: nil, verticalAccuracy: nil))
        XCTAssertNotNil(makeFix(altitude: 10, verticalAccuracy: 3))
        XCTAssertNotNil(makeFix(altitude: -5, verticalAccuracy: 0))
    }

    /// 責務: 標高と垂直精度の片方だけが値ありなら nil になることを確かめます。
    func testAltitudePairHalfPresentIsRejected() {
        XCTAssertNil(makeFix(altitude: 10, verticalAccuracy: nil))
        XCTAssertNil(makeFix(altitude: nil, verticalAccuracy: 3))
    }

    /// 責務: 垂直精度が負なら nil になることを確かめます。
    func testNegativeVerticalAccuracyIsRejected() {
        XCTAssertNil(makeFix(altitude: 10, verticalAccuracy: -0.001))
    }

    /// 責務: 標高が NaN や無限大なら nil になることを確かめます。
    func testNonFiniteAltitudeIsRejected() {
        XCTAssertNil(makeFix(altitude: .nan, verticalAccuracy: 3))
        XCTAssertNil(makeFix(altitude: .infinity, verticalAccuracy: 3))
        XCTAssertNil(makeFix(altitude: -.infinity, verticalAccuracy: 3))
    }

    /// 責務: 速度が nil と 0 なら有効なことを確かめます。
    func testSpeedNilAndZeroAreValid() {
        XCTAssertNotNil(makeFix(speed: nil))
        XCTAssertNotNil(makeFix(speed: 0))
        XCTAssertNotNil(makeFix(speed: 30.5))
    }

    /// 責務: 速度が負・NaN・無限大なら nil になることを確かめます。
    func testInvalidSpeedIsRejected() {
        XCTAssertNil(makeFix(speed: -0.001))
        XCTAssertNil(makeFix(speed: .nan))
        XCTAssertNil(makeFix(speed: .infinity))
    }

    /// 責務: 進行方向が nil・0・359.9 なら有効なことを確かめます。
    func testCourseValidValues() {
        XCTAssertNotNil(makeFix(course: nil))
        XCTAssertNotNil(makeFix(course: 0))
        XCTAssertNotNil(makeFix(course: 359.9))
    }

    /// 責務: 進行方向が 360 以上・負・NaN なら nil になることを確かめます。
    func testInvalidCourseIsRejected() {
        XCTAssertNil(makeFix(course: 360))
        XCTAssertNil(makeFix(course: -0.001))
        XCTAssertNil(makeFix(course: .nan))
    }
}
