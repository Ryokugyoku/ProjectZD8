import CoreLocation
import MapKit
import XCTest
@testable import ProjectZD8

/// `RouteMapFraming` の表示範囲の計算(余白・最小の広がり・切り詰め・設定値の補正)を、管理役が確定した式から独立に計算した値で検証します。
@MainActor
final class RouteMapFramingTests: XCTestCase {
    private let degrees = GeoBoundingBox.metersPerDegree
    private let accuracy = 1e-9

    /// 責務: 4辺から外接矩形を作ります(無効ならテストの誤りとして失敗させます)。
    private func box(_ minLat: Double, _ maxLat: Double, _ minLon: Double, _ maxLon: Double) throws -> GeoBoundingBox {
        try XCTUnwrap(GeoBoundingBox(minLatitude: minLat, maxLatitude: maxLat, minLongitude: minLon, maxLongitude: maxLon))
    }

    /// 責務: 4辺が期待値と 1e-9 度以内で一致することを確かめます。
    private func assertBounds(
        _ actual: GeoBoundingBox,
        _ minLat: Double, _ maxLat: Double, _ minLon: Double, _ maxLon: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.minLatitude, minLat, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.maxLatitude, maxLat, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minLongitude, minLon, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.maxLongitude, maxLon, accuracy: accuracy, file: file, line: line)
    }

    // MARK: 設定値

    /// 責務: 標準の余白の割合が 0.15、最小の広がりが 400 m であることを確かめます。
    func testDefaultSettings() {
        let framing = RouteMapFraming()
        XCTAssertEqual(framing.paddingRatio, 0.15)
        XCTAssertEqual(framing.minimumSpanMeters, 400)
    }

    /// 責務: 負の値・NaN・無限大の設定値が 0 とみなされることを確かめます。
    func testInvalidSettingsBecomeZero() {
        for value in [-1.0, -0.001, Double.nan, Double.infinity, -Double.infinity] {
            let framing = RouteMapFraming(paddingRatio: value, minimumSpanMeters: value)
            XCTAssertEqual(framing.paddingRatio, 0, "\(value)")
            XCTAssertEqual(framing.minimumSpanMeters, 0, "\(value)")
        }
    }

    /// 責務: 0 と正の設定値はそのまま保たれることを確かめます。
    func testValidSettingsArePreserved() {
        let framing = RouteMapFraming(paddingRatio: 0, minimumSpanMeters: 250)
        XCTAssertEqual(framing.paddingRatio, 0)
        XCTAssertEqual(framing.minimumSpanMeters, 250)
    }

    // MARK: 余白

    /// 責務: 大きな範囲で、幅・高さが元の 1 + 2 × 0.15 = 1.3 倍になり、中心が変わらないことを確かめます。
    func testLargeBoundsGetFifteenPercentPaddingOnEachSide() throws {
        let framed = RouteMapFraming().framedBounds(for: try box(26.0, 26.02, 127.6, 127.64))
        assertBounds(framed, 26.01 - 0.013, 26.01 + 0.013, 127.62 - 0.026, 127.62 + 0.026)
    }

    /// 責務: 緯度と経度の余白が、それぞれの幅の割合で別々に付くことを確かめます。
    func testPaddingIsPerAxis() throws {
        let framed = RouteMapFraming().framedBounds(for: try box(26.0, 26.01, 127.0, 127.1))
        XCTAssertEqual(framed.maxLatitude - framed.minLatitude, 0.013, accuracy: accuracy)
        XCTAssertEqual(framed.maxLongitude - framed.minLongitude, 0.13, accuracy: accuracy)
    }

    /// 責務: 余白の割合 0 では、範囲が大きければ元のままになることを確かめます。
    func testZeroPaddingKeepsLargeBounds() throws {
        let framed = RouteMapFraming(paddingRatio: 0, minimumSpanMeters: 0).framedBounds(for: try box(26.0, 26.02, 127.6, 127.64))
        assertBounds(framed, 26.0, 26.02, 127.6, 127.64)
    }

    /// 責務: 余白の割合を 0.5 にすると、幅・高さが 2 倍になることを確かめます。
    func testCustomPaddingRatio() throws {
        let framed = RouteMapFraming(paddingRatio: 0.5).framedBounds(for: try box(26.0, 26.02, 127.6, 127.64))
        assertBounds(framed, 26.01 - 0.02, 26.01 + 0.02, 127.62 - 0.04, 127.62 + 0.04)
    }

    // MARK: 最小の広がり

    /// 責務: 1点だけの時に、400 m 四方相当(緯度は ±200 m / 111,195.08、経度は余弦で割る)になることを確かめます。
    func testSinglePointGetsMinimumSpan() throws {
        let framed = RouteMapFraming().framedBounds(for: try box(26.2, 26.2, 127.7, 127.7))
        let latitudeHalf = 200 / degrees
        let longitudeHalf = 200 / (degrees * cos(26.2 * Double.pi / 180))
        assertBounds(framed, 26.2 - latitudeHalf, 26.2 + latitudeHalf, 127.7 - longitudeHalf, 127.7 + longitudeHalf)
        XCTAssertEqual((framed.maxLatitude - framed.minLatitude) * degrees, 400, accuracy: 0.01)
    }

    /// 責務: 極端に小さい範囲(約 10 m)でも、最小の広がりになることを確かめます。
    func testTinyBoundsGetMinimumSpan() throws {
        let tiny = 10 / degrees
        let framed = RouteMapFraming().framedBounds(for: try box(26.2, 26.2 + tiny, 127.7, 127.7 + tiny))
        XCTAssertEqual((framed.maxLatitude - framed.minLatitude) * degrees, 400, accuracy: 0.01)
        let width = (framed.maxLongitude - framed.minLongitude) * degrees * cos((26.2 + tiny / 2) * Double.pi / 180)
        XCTAssertEqual(width, 400, accuracy: 0.01)
        XCTAssertEqual((framed.minLatitude + framed.maxLatitude) / 2, 26.2 + tiny / 2, accuracy: accuracy)
        XCTAssertEqual((framed.minLongitude + framed.maxLongitude) / 2, 127.7 + tiny / 2, accuracy: accuracy)
    }

    /// 責務: 余白込みの幅が最小の広がりより小さい側だけが最小に引き上げられ、大きい側は余白だけが付くことを確かめます。
    func testMinimumAppliesPerAxis() throws {
        let latitudeSpan = 0.02
        let framed = RouteMapFraming().framedBounds(for: try box(26.0, 26.0 + latitudeSpan, 127.7, 127.7))
        XCTAssertEqual(framed.maxLatitude - framed.minLatitude, latitudeSpan * 1.3, accuracy: accuracy)
        let longitudeSpan = framed.maxLongitude - framed.minLongitude
        XCTAssertEqual(longitudeSpan, 400 / (degrees * cos(26.01 * Double.pi / 180)), accuracy: accuracy)
    }

    /// 責務: 余白込みの幅がちょうど最小の広がりを超える範囲では、余白込みの幅が使われる(最小に丸められない)ことを確かめます。
    func testPaddedSpanLargerThanMinimumIsNotRaised() throws {
        let span = 500 / degrees
        let framed = RouteMapFraming().framedBounds(for: try box(26.2, 26.2 + span, 127.7, 127.7 + span))
        XCTAssertEqual((framed.maxLatitude - framed.minLatitude) * degrees, 650, accuracy: 0.01)
    }

    /// 責務: 最小の広がりを 1,000 m にすると、1点が 1,000 m 四方相当になることを確かめます。
    func testCustomMinimumSpan() throws {
        let framed = RouteMapFraming(minimumSpanMeters: 1_000).framedBounds(for: try box(10, 10, 20, 20))
        XCTAssertEqual((framed.maxLatitude - framed.minLatitude) * degrees, 1_000, accuracy: 0.01)
    }

    /// 責務: 最小の広がりが 0 で余白も 0 なら、1点は幅 0 のままであることを確かめます。
    func testZeroMinimumKeepsSinglePoint() throws {
        let framed = RouteMapFraming(paddingRatio: 0, minimumSpanMeters: 0).framedBounds(for: try box(26.2, 26.2, 127.7, 127.7))
        assertBounds(framed, 26.2, 26.2, 127.7, 127.7)
    }

    // MARK: 切り詰め

    /// 責務: 北端が Web メルカトルの上限 85.05112878 度を超える時、緯度が上限で切り詰められることを確かめます。
    func testLatitudeIsClampedAtMercatorLimit() throws {
        let framed = RouteMapFraming().framedBounds(for: try box(85.0, 85.05, 10, 10.1))
        XCTAssertEqual(framed.maxLatitude, 85.051_128_78, accuracy: accuracy)
        XCTAssertEqual(framed.minLatitude, 85.025 - 0.0325, accuracy: accuracy)
        XCTAssertEqual(RouteMapFraming.mercatorLatitudeLimit, 85.051_128_78)
    }

    /// 責務: 南端も同様に -85.05112878 度で切り詰められることを確かめます。
    func testSouthernLatitudeIsClamped() throws {
        let framed = RouteMapFraming().framedBounds(for: try box(-85.05, -85.0, 10, 10.1))
        XCTAssertEqual(framed.minLatitude, -85.051_128_78, accuracy: accuracy)
    }

    /// 責務: 経度が ±180 度で切り詰められることを確かめます。
    func testLongitudeIsClampedAtAntimeridian() throws {
        let east = RouteMapFraming().framedBounds(for: try box(10, 10.1, 179.9, 180))
        XCTAssertEqual(east.maxLongitude, 180, accuracy: accuracy)
        XCTAssertEqual(east.minLongitude, 179.95 - 0.065, accuracy: accuracy)
        let west = RouteMapFraming().framedBounds(for: try box(10, 10.1, -180, -179.9))
        XCTAssertEqual(west.minLongitude, -180, accuracy: accuracy)
    }

    /// 責務: 全経度の範囲でも、広がりが 360 度で頭打ちになることを確かめます。
    func testSpanIsCappedAtFullCircle() throws {
        let framed = RouteMapFraming().framedBounds(for: try box(0, 10, -180, 180))
        XCTAssertEqual(framed.minLongitude, -180, accuracy: accuracy)
        XCTAssertEqual(framed.maxLongitude, 180, accuracy: accuracy)
    }
}
