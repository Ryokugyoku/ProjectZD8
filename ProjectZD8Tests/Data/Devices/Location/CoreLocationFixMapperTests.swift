import CoreLocation
import Foundation
import XCTest
@testable import ProjectZD8

/// `CoreLocationFixMapper` の無効値の除去と単調時刻の補正を検証します。
final class CoreLocationFixMapperTests: XCTestCase {
    /// 受信時の実時間です。2進で正確に表せる値にして秒の計算を厳密にします。
    private let wallNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
    /// 受信時の単調時計です。
    private let monotonicNow: UInt64 = 10_000_000_000

    /// 指定の精度・値で `CLLocation` を作ります。
    ///
    /// 責務: 既定で全項目が有効な位置を作り、引数で指定した項目だけを差し替えます。
    private func makeLocation(
        horizontal: Double = 5, vertical: Double = 8, speed: Double = 12, speedAccuracy: Double = 1,
        course: Double = 90, courseAccuracy: Double = 2, timestamp: Date? = nil
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.5, longitude: 139.25), altitude: 42,
            horizontalAccuracy: horizontal, verticalAccuracy: vertical, course: course, courseAccuracy: courseAccuracy,
            speed: speed, speedAccuracy: speedAccuracy, timestamp: timestamp ?? wallNow)
    }

    /// 位置をマッピングします。
    ///
    /// 責務: 固定の受信時刻でマッパーを呼びます。
    private func map(_ location: CLLocation) -> LocationFix? {
        CoreLocationFixMapper().fix(from: location, wallNow: wallNow, monotonicNow: monotonicNow)
    }

    /// 有効な位置の値がそのまま保たれます。
    ///
    /// 責務: 緯度・経度・水平精度・observedAt・標高・垂直精度・速度・進行方向を確認します。
    func testValidLocationKeepsAllValues() throws {
        let timestamp = wallNow.addingTimeInterval(-1)
        let fix = try XCTUnwrap(map(makeLocation(timestamp: timestamp)))

        XCTAssertEqual(fix.latitude, 35.5)
        XCTAssertEqual(fix.longitude, 139.25)
        XCTAssertEqual(fix.horizontalAccuracyMeters, 5)
        XCTAssertEqual(fix.observedAt, timestamp)
        XCTAssertEqual(fix.altitudeMeters, 42)
        XCTAssertEqual(fix.verticalAccuracyMeters, 8)
        XCTAssertEqual(fix.speedMetersPerSecond, 12)
        XCTAssertEqual(fix.courseDegrees, 90)
    }

    /// 水平精度が負なら捨てます。0 は有効です。
    ///
    /// 責務: 水平精度の境界(負・0)を確認します。
    func testNegativeHorizontalAccuracyIsRejectedAndZeroIsValid() throws {
        XCTAssertNil(map(makeLocation(horizontal: -1)))
        let fix = try XCTUnwrap(map(makeLocation(horizontal: 0)))
        XCTAssertEqual(fix.horizontalAccuracyMeters, 0)
    }

    /// 垂直精度が負なら標高と垂直精度がどちらも nil で、点は残ります。
    ///
    /// 責務: 垂直精度の境界(負・0)を確認します。
    func testNegativeVerticalAccuracyDropsAltitudeButKeepsFix() throws {
        let invalid = try XCTUnwrap(map(makeLocation(vertical: -1)))
        XCTAssertNil(invalid.altitudeMeters)
        XCTAssertNil(invalid.verticalAccuracyMeters)

        let zero = try XCTUnwrap(map(makeLocation(vertical: 0)))
        XCTAssertEqual(zero.altitudeMeters, 42)
        XCTAssertEqual(zero.verticalAccuracyMeters, 0)
    }

    /// 速度精度が負、または速度が負なら速度は nil です。
    ///
    /// 責務: 速度と速度精度の無効・境界(0)の組み合わせを確認します。
    func testSpeedIsNilWhenSpeedOrItsAccuracyIsNegative() throws {
        XCTAssertNil(try XCTUnwrap(map(makeLocation(speedAccuracy: -1))).speedMetersPerSecond)
        XCTAssertNil(try XCTUnwrap(map(makeLocation(speed: -1))).speedMetersPerSecond)
        XCTAssertEqual(try XCTUnwrap(map(makeLocation(speed: 0, speedAccuracy: 0))).speedMetersPerSecond, 0)
    }

    /// 進行方向精度が負、または進行方向が負なら進行方向は nil です。
    ///
    /// 責務: 進行方向と精度の無効・境界(0、359.9)の組み合わせを確認します。
    func testCourseIsNilWhenCourseOrItsAccuracyIsNegative() throws {
        XCTAssertNil(try XCTUnwrap(map(makeLocation(courseAccuracy: -1))).courseDegrees)
        XCTAssertNil(try XCTUnwrap(map(makeLocation(course: -1))).courseDegrees)
        XCTAssertEqual(try XCTUnwrap(map(makeLocation(course: 0, courseAccuracy: 0))).courseDegrees, 0)
        XCTAssertEqual(try XCTUnwrap(map(makeLocation(course: 359.9))).courseDegrees, 359.9)
    }

    /// 無効な速度・進行方向・垂直精度が重なっても点は残ります。
    ///
    /// 責務: 水平精度だけが有効な位置から、位置だけの fix が作られることを確認します。
    func testOnlyHorizontalValidLocationYieldsPositionOnlyFix() throws {
        let location = makeLocation(vertical: -1, speed: -1, speedAccuracy: -1, course: -1, courseAccuracy: -1)
        let fix = try XCTUnwrap(map(location))

        XCTAssertNil(fix.altitudeMeters)
        XCTAssertNil(fix.verticalAccuracyMeters)
        XCTAssertNil(fix.speedMetersPerSecond)
        XCTAssertNil(fix.courseDegrees)
    }

    /// 位置が2秒前なら、単調時刻は受信時の単調時計より2秒前です。
    ///
    /// 責務: 位置の古さぶんだけ単調時刻が戻ることを確認します。
    func testMonotonicTimeIsShiftedByLocationAge() throws {
        let fix = try XCTUnwrap(map(makeLocation(timestamp: wallNow.addingTimeInterval(-2))))
        XCTAssertEqual(fix.monotonicNanoseconds, monotonicNow - 2_000_000_000)
    }

    /// 位置の時刻が受信時の実時間と同じか未来なら、単調時刻は受信時のままです。
    ///
    /// 責務: 古さの下限0への切り詰めを確認します。
    func testMonotonicTimeIsUnchangedForZeroOrFutureAge() throws {
        let same = try XCTUnwrap(map(makeLocation(timestamp: wallNow)))
        XCTAssertEqual(same.monotonicNanoseconds, monotonicNow)

        let future = try XCTUnwrap(map(makeLocation(timestamp: wallNow.addingTimeInterval(5))))
        XCTAssertEqual(future.monotonicNanoseconds, monotonicNow)
    }

    /// 位置の古さが単調時計より大きくても0で止まり、アンダーフローしません。
    ///
    /// 責務: 古さが単調時計の値を超える場合と、ちょうど等しい場合を確認します。
    func testMonotonicTimeClampsAtZeroWithoutUnderflow() throws {
        let older = try XCTUnwrap(map(makeLocation(timestamp: wallNow.addingTimeInterval(-100))))
        XCTAssertEqual(older.monotonicNanoseconds, 0)

        let exact = try XCTUnwrap(map(makeLocation(timestamp: wallNow.addingTimeInterval(-10))))
        XCTAssertEqual(exact.monotonicNanoseconds, 0)
    }
}
