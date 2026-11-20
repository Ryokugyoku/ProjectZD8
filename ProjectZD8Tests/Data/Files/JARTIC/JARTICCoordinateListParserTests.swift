import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICCoordinateListParser` が、「経度 緯度」の並び(`;` で点、`/` で区間)を点列にし、不正な値を `nil` にすることを検証します。
@MainActor
final class JARTICCoordinateListParserTests: XCTestCase {
    private let parser = JARTICCoordinateListParser()

    private func parse(_ text: String) -> [[GeoCoordinate]]? {
        parser.parse(Array(text.utf8)[...])
    }

    private func point(_ longitude: Double, _ latitude: Double) -> GeoCoordinate {
        TestJARTICRegulationRowBuilder.coordinate(longitude: longitude, latitude: latitude)
    }

    // MARK: 空・基本

    /// 空の項目は、失敗ではなく区間なしの `[]` です。
    func testEmptyFieldReturnsNoSegments() {
        XCTAssertEqual(parse(""), [])
    }

    /// 空白だけの項目も `[]` です。
    func testBlankFieldReturnsNoSegments() {
        XCTAssertEqual(parse("   "), [])
    }

    /// 1点だけの項目は、1区間・1点になります。
    func testSinglePoint() {
        XCTAssertEqual(parse("127.5 26.2"), [[point(127.5, 26.2)]])
    }

    /// 経度が先、緯度が後です。緯度と経度を取り違えると、値が入れ替わって失敗します。
    func testLongitudeComesFirst() throws {
        let first = try XCTUnwrap(parse("127.5 26.2")?.first?.first)
        XCTAssertEqual(first.longitude, 127.5, accuracy: 1e-9)
        XCTAssertEqual(first.latitude, 26.2, accuracy: 1e-9)
    }

    /// 緯度と経度の順で書かれた値は、範囲外になり `nil` です。
    func testSwappedOrderIsRejected() {
        XCTAssertNil(parse("26.2 127.5"))
    }

    // MARK: 区切り

    /// `;` で点に分けます(順序を保つ)。
    func testSemicolonSeparatesPoints() {
        XCTAssertEqual(parse("127.5 26.2;127.6 26.3;127.7 26.4"), [[point(127.5, 26.2), point(127.6, 26.3), point(127.7, 26.4)]])
    }

    /// `/` で区間に分けます。
    func testSlashSeparatesSegments() {
        XCTAssertEqual(
            parse("127.5 26.2;127.6 26.3/127.7 26.4;127.8 26.5"),
            [[point(127.5, 26.2), point(127.6, 26.3)], [point(127.7, 26.4), point(127.8, 26.5)]]
        )
    }

    /// 経度と緯度の間が空白2つ以上でも読めます。
    func testMultipleSpacesBetweenLongitudeAndLatitude() {
        XCTAssertEqual(parse("127.5  26.2;127.6    26.3"), [[point(127.5, 26.2), point(127.6, 26.3)]])
    }

    /// 項目の前後の空白は無視します。
    func testLeadingAndTrailingWhitespaceIsIgnored() {
        XCTAssertEqual(parse("  127.5 26.2;127.6 26.3  "), [[point(127.5, 26.2), point(127.6, 26.3)]])
    }

    /// `;` の前後の空白は無視します。
    func testWhitespaceAroundSemicolonIsIgnored() {
        XCTAssertEqual(parse("127.5 26.2 ; 127.6 26.3"), [[point(127.5, 26.2), point(127.6, 26.3)]])
    }

    // MARK: 連続する同じ点

    /// 連続する同じ点は1つにまとめます。
    func testConsecutiveDuplicatePointsAreMerged() {
        XCTAssertEqual(parse("127.5 26.2;127.5 26.2;127.6 26.3;127.6 26.3"), [[point(127.5, 26.2), point(127.6, 26.3)]])
    }

    /// 表記が違っても同じ値(127.5 と 127.50)ならまとめます。
    func testDuplicatesAreComparedByValue() {
        XCTAssertEqual(parse("127.5 26.2;127.50 26.20"), [[point(127.5, 26.2)]])
    }

    /// 離れた位置の同じ点(折り返し・閉じた形)はまとめません。
    func testNonConsecutiveDuplicatesAreKept() {
        XCTAssertEqual(parse("127.5 26.2;127.6 26.3;127.5 26.2"), [[point(127.5, 26.2), point(127.6, 26.3), point(127.5, 26.2)]])
    }
}
