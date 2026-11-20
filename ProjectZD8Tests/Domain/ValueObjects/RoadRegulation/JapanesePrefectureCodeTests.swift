import XCTest
@testable import ProjectZD8

/// `JapanesePrefectureCode` の初期化の境界(1〜47)、2桁表記、順序を検証します。
final class JapanesePrefectureCodeTests: XCTestCase {
    /// 責務: 1〜47 が成功し、0・48・負の値が失敗することを確かめます。
    func testValidRangeBoundaries() {
        XCTAssertNotNil(JapanesePrefectureCode(1))
        XCTAssertNotNil(JapanesePrefectureCode(47))
        XCTAssertNil(JapanesePrefectureCode(0))
        XCTAssertNil(JapanesePrefectureCode(48))
        XCTAssertNil(JapanesePrefectureCode(-1))
        XCTAssertEqual(JapanesePrefectureCode.validRange, 1...47)
    }

    /// 責務: 全コードが47件で、1〜47の昇順であることを確かめます。
    func testAllContainsFortySevenCodesInOrder() {
        XCTAssertEqual(JapanesePrefectureCode.all.map(\.rawValue), Array(1...47))
    }

    /// 責務: 2桁表記が、1桁は 0 埋め、2桁はそのままになることを確かめます。
    func testTwoDigitText() {
        XCTAssertEqual(JapanesePrefectureCode(1)?.twoDigitText, "01")
        XCTAssertEqual(JapanesePrefectureCode(9)?.twoDigitText, "09")
        XCTAssertEqual(JapanesePrefectureCode(10)?.twoDigitText, "10")
        XCTAssertEqual(JapanesePrefectureCode(47)?.twoDigitText, "47")
    }

    /// 責務: 値の大小で比較され、同じ値は等しいことを確かめます。
    func testOrderingAndEquality() throws {
        let tokyo = try XCTUnwrap(JapanesePrefectureCode(13))
        let okinawa = try XCTUnwrap(JapanesePrefectureCode(47))
        XCTAssertLessThan(tokyo, okinawa)
        XCTAssertFalse(okinawa < tokyo)
        XCTAssertEqual(tokyo, JapanesePrefectureCode(13))
        XCTAssertEqual(Set([tokyo, JapanesePrefectureCode(13)]).count, 1)
    }
}
