import XCTest
@testable import ProjectZD8

/// `GeoDistanceCalculator` の距離・方位・角度差を、設計書 §3.3 の値と独立に計算した値で検証します。
final class GeoDistanceCalculatorTests: XCTestCase {
    private let calculator = GeoDistanceCalculator()

    /// 責務: 緯度・経度から座標を作ります(範囲外ならテストの誤りとして失敗させます)。
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> GeoCoordinate {
        try XCTUnwrap(GeoCoordinate(latitude: latitude, longitude: longitude))
    }

    // MARK: distanceMeters

    /// 責務: 設計書の例 (35, 139) → (35, 139.001) が 91.086 m であることを確かめます。
    func testDistanceAlongLongitudeAtLatitude35() throws {
        let distance = calculator.distanceMeters(try coordinate(35, 139), try coordinate(35, 139.001))
        XCTAssertEqual(distance, 91.086, accuracy: 0.01)
    }

    /// 責務: 設計書の例 (0, 0) → (1, 0) が 111,195.08 m であることを確かめます。
    func testDistanceOneDegreeOfLatitude() throws {
        let distance = calculator.distanceMeters(try coordinate(0, 0), try coordinate(1, 0))
        XCTAssertEqual(distance, 111_195.08, accuracy: 0.01)
    }

    /// 責務: 同じ点どうしの距離が 0 であることを確かめます。
    func testDistanceOfSamePointIsZero() throws {
        let point = try coordinate(26.2, 127.7)
        XCTAssertEqual(calculator.distanceMeters(point, point), 0, accuracy: 1e-9)
    }

    /// 責務: 引数を入れ替えても距離が同じであることを確かめます。
    func testDistanceIsSymmetric() throws {
        let a = try coordinate(35, 139)
        let b = try coordinate(35.01, 139.02)
        XCTAssertEqual(calculator.distanceMeters(a, b), calculator.distanceMeters(b, a), accuracy: 1e-9)
    }

    /// 責務: 赤道上の経度1度が 111,195.08 m(cos 0 = 1)であることを確かめます。
    func testDistanceOneDegreeOfLongitudeOnEquator() throws {
        let distance = calculator.distanceMeters(try coordinate(0, 0), try coordinate(0, 1))
        XCTAssertEqual(distance, 111_195.08, accuracy: 0.01)
    }

    /// 責務: 基準緯度が2点の平均であること(北緯60度どうしで cos 60° = 0.5)を確かめます。
    /// 期待値は 111,195.0802 × 0.5 = 55,597.540 m(独立に計算)。
    func testDistanceUsesMeanLatitudeForLongitudeScale() throws {
        let distance = calculator.distanceMeters(try coordinate(60, 10), try coordinate(60, 11))
        XCTAssertEqual(distance, 55_597.54, accuracy: 0.01)
    }

    /// 責務: 東西・南北の差が両方ある時にピタゴラスで合成することを確かめます。
    /// 赤道付近の (0,0)→(0.001,0.001) は √2 × 111.19508 = 157.2536 m(平均緯度の cos 補正は 4e-8 程度で許容誤差内)。
    func testDistanceCombinesBothAxes() throws {
        let distance = calculator.distanceMeters(try coordinate(0, 0), try coordinate(0.001, 0.001))
        XCTAssertEqual(distance, 157.2536, accuracy: 0.01)
    }

    /// 責務: 経度 ±180 度をまたぐ2点が、設計書の式(経度差をそのまま使う。折り返さない)で計算されることを確かめます。
    /// (0, 179.999) → (0, -179.999) は経度差 -359.998 度 × 111,195.08(設計書 §3.3 の k)= 40,030,006.41 m。
    /// 4万 km に対する k の丸め(0.0002 m/度)の影響を見込み、許容誤差は 0.1 m とする。
    func testDistanceAcrossAntimeridianUsesPlainLongitudeDifference() throws {
        let distance = calculator.distanceMeters(try coordinate(0, 179.999), try coordinate(0, -179.999))
        XCTAssertEqual(distance, 40_030_006.41, accuracy: 0.1)
    }

    // MARK: bearingDegrees

    /// 責務: 真北・真東・真南・真西の方位が 0 / 90 / 180 / 270 であることを確かめます。
    func testBearingOfCardinalDirections() throws {
        let origin = try coordinate(35, 139)
        XCTAssertEqual(try XCTUnwrap(calculator.bearingDegrees(from: origin, to: try coordinate(35.001, 139))), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(calculator.bearingDegrees(from: origin, to: try coordinate(35, 139.001))), 90, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(calculator.bearingDegrees(from: origin, to: try coordinate(34.999, 139))), 180, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(calculator.bearingDegrees(from: origin, to: try coordinate(35, 138.999))), 270, accuracy: 1e-9)
    }

    /// 責務: 同じ点では方位が `nil` であることを確かめます。
    func testBearingOfSamePointIsNil() throws {
        let point = try coordinate(35, 139)
        XCTAssertNil(calculator.bearingDegrees(from: point, to: point))
    }

    /// 責務: 斜め方向の方位(北東45度・南西225度・北西315度)が 0..<360 で返ることを確かめます。
    /// 赤道付近では x = y となる点が 45度(誤差は 1e-8 度未満)。
    func testBearingOfDiagonalDirections() throws {
        let origin = try coordinate(0, 0)
        XCTAssertEqual(try XCTUnwrap(calculator.bearingDegrees(from: origin, to: try coordinate(0.001, 0.001))), 45, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(calculator.bearingDegrees(from: origin, to: try coordinate(-0.001, -0.001))), 225, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(calculator.bearingDegrees(from: origin, to: try coordinate(0.001, -0.001))), 315, accuracy: 1e-4)
    }

    /// 責務: 返る方位が常に 0 以上 360 未満であることを、全方位の点で確かめます。
    func testBearingIsAlwaysInHalfOpenRange() throws {
        let origin = try coordinate(35, 139)
        for step in 0..<72 {
            let radians = Double(step) * 5 * Double.pi / 180
            let target = try coordinate(35 + 0.001 * cos(radians), 139 + 0.001 * sin(radians))
            let bearing = try XCTUnwrap(calculator.bearingDegrees(from: origin, to: target))
            XCTAssertGreaterThanOrEqual(bearing, 0)
            XCTAssertLessThan(bearing, 360)
        }
    }

    // MARK: angularDifference

    /// 責務: 設計書の例 (350, 10) = 20、(0, 180) = 180、(90, 90) = 0 を確かめます。
    func testAngularDifferenceExamples() {
        XCTAssertEqual(calculator.angularDifference(350, 10), 20, accuracy: 1e-9)
        XCTAssertEqual(calculator.angularDifference(0, 180), 180, accuracy: 1e-9)
        XCTAssertEqual(calculator.angularDifference(90, 90), 0, accuracy: 1e-9)
    }

    /// 責務: 引数の順序に依らないこと、180度を超える差が折り返されること(270 と 0 は 90)を確かめます。
    func testAngularDifferenceIsSymmetricAndWrapsAround() {
        XCTAssertEqual(calculator.angularDifference(10, 350), 20, accuracy: 1e-9)
        XCTAssertEqual(calculator.angularDifference(270, 0), 90, accuracy: 1e-9)
        XCTAssertEqual(calculator.angularDifference(0, 270), 90, accuracy: 1e-9)
        XCTAssertEqual(calculator.angularDifference(181, 0), 179, accuracy: 1e-9)
    }

    /// 責務: 差がちょうど 360 や 0..<360 の端(0 と 359.5)でも 0...180 に収まることを確かめます。
    func testAngularDifferenceAtRangeEdges() {
        XCTAssertEqual(calculator.angularDifference(0, 360), 0, accuracy: 1e-9)
        XCTAssertEqual(calculator.angularDifference(0, 359.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(calculator.angularDifference(45, 225), 180, accuracy: 1e-9)
    }
}
