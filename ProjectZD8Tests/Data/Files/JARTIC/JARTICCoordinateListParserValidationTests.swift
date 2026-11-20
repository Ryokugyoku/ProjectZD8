import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICCoordinateListParser` が、範囲外・数値でない値・欠けた点を `nil` にすることを検証します。
@MainActor
final class JARTICCoordinateListParserValidationTests: XCTestCase {
    private let parser = JARTICCoordinateListParser()

    private func parse(_ text: String) -> [[GeoCoordinate]]? {
        parser.parse(Array(text.utf8)[...])
    }

    // MARK: 範囲

    /// 緯度 20.0 と 46.0(端)は有効です。
    func testLatitudeBoundsAreInclusive() {
        XCTAssertNotNil(parse("127.5 20.0"))
        XCTAssertNotNil(parse("127.5 46.0"))
    }

    /// 緯度が 20 未満・46 超は `nil` です。
    func testLatitudeOutsideBoundsIsRejected() {
        XCTAssertNil(parse("127.5 19.99"))
        XCTAssertNil(parse("127.5 46.01"))
    }

    /// 経度 122.0 と 154.0(端)は有効です。
    func testLongitudeBoundsAreInclusive() {
        XCTAssertNotNil(parse("122.0 26.2"))
        XCTAssertNotNil(parse("154.0 26.2"))
    }

    /// 経度が 122 未満・154 超は `nil` です。
    func testLongitudeOutsideBoundsIsRejected() {
        XCTAssertNil(parse("121.99 26.2"))
        XCTAssertNil(parse("154.01 26.2"))
    }

    // MARK: 不正な値

    /// 数値でない値は `nil` です。
    func testNonNumericValueIsRejected() {
        XCTAssertNil(parse("abc def"))
        XCTAssertNil(parse("127.5 north"))
    }

    /// 有限でない値(nan・inf)は `nil` です。
    func testNonFiniteValueIsRejected() {
        XCTAssertNil(parse("nan 26.2"))
        XCTAssertNil(parse("127.5 inf"))
    }

    /// 緯度が欠けた点(数値が1つだけ)は `nil` です。
    func testPointWithOnlyOneNumberIsRejected() {
        XCTAssertNil(parse("127.5"))
        XCTAssertNil(parse("127.5 26.2;127.6"))
    }

    /// ASCII 以外のバイトを含む値は `nil` です。
    func testNonASCIIBytesAreRejected() {
        XCTAssertNil(parser.parse([0x31, 0x32, 0x37, 0x2E, 0x35, 0x20, 0x82, 0xA0][...]))
    }

    /// 1点でも不正なら、全体が `nil` です(後ろの区間でも同じ)。
    func testOneInvalidPointInvalidatesWholeField() {
        XCTAssertNil(parse("127.5 26.2;abc def;127.7 26.4"))
        XCTAssertNil(parse("127.5 26.2;127.6 26.3/127.7 99.0;127.8 26.5"))
    }
}
