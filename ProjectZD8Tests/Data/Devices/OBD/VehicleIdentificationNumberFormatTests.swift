import XCTest
@testable import ProjectZD8

/// `VehicleIdentificationNumberFormat` が、17文字で I・O・Q を含まない英大文字と数字だけの文字列を VIN と判定することを検証します。
final class VehicleIdentificationNumberFormatTests: XCTestCase {
    /// 検証対象の書式です。
    private let format = VehicleIdentificationNumberFormat()

    /// 妥当な17文字のVINです。
    private static let valid = "JF1ZD8A11P9000001"

    /// 17文字の英大文字・数字(I・O・Q 以外)は妥当です。
    ///
    /// 責務: 代表値と、使える文字を網羅した17文字が妥当になることを確認します。
    func testSeventeenAllowedCharactersAreValid() {
        XCTAssertTrue(format.isValid(Self.valid))
        XCTAssertTrue(format.isValid("ABCDEFGHJKLMNPRST"))
        XCTAssertTrue(format.isValid("UVWXYZ01234567890"))
        XCTAssertEqual(VehicleIdentificationNumberFormat.length, 17)
    }

    /// 16文字・18文字・空は妥当ではありません。
    ///
    /// 責務: 長さの境界を確認します。
    func testLengthBoundaries() {
        XCTAssertFalse(format.isValid(String(Self.valid.dropLast())))
        XCTAssertFalse(format.isValid(Self.valid + "1"))
        XCTAssertFalse(format.isValid(""))
    }

    /// I・O・Q を1文字でも含めば妥当ではありません。
    ///
    /// 責務: 禁止文字をそれぞれ末尾に置いた17文字が妥当でないことを確認します。
    func testForbiddenLettersAreInvalid() {
        for letter in ["I", "O", "Q"] {
            XCTAssertFalse(format.isValid(String(Self.valid.dropLast()) + letter), letter)
        }
    }

    /// 小文字・空白・記号・全角文字を含む17文字は妥当ではありません。
    ///
    /// 責務: 英大文字と数字以外の文字が混じる場合を確認します。
    func testOtherCharactersAreInvalid() {
        let base = String(Self.valid.dropLast())
        for character in ["a", " ", "-", "\n", "\u{FF21}"] {
            XCTAssertFalse(format.isValid(base + character), character.debugDescription)
        }
        XCTAssertFalse(format.isValid(Self.valid.lowercased()))
    }

    /// 前後に空白がある VIN は(17文字でなくなるので)妥当ではありません。
    ///
    /// 責務: 空白混じりの読み取り値をそのまま VIN と認めないことを確認します。
    func testSurroundingWhitespaceIsInvalid() {
        XCTAssertFalse(format.isValid(" \(Self.valid)"))
        XCTAssertFalse(format.isValid("\(Self.valid) "))
        XCTAssertFalse(format.isValid("JF1ZD8A11 P900000"))
    }
}
