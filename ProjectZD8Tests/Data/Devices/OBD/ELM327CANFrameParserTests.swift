import XCTest
@testable import ProjectZD8

/// ATMA受信行のCANフレーム解析を検証します。
@MainActor
final class ELM327CANFrameParserTests: XCTestCase {
    private let parser = ELM327CANFrameParser()

    /// 解析結果が期待どおりのフレームであることを確認します。
    ///
    /// 責務: 行を解析し、ID・拡張フラグ・payloadを比較します。
    private func assertFrame(
        _ line: String, id: UInt32, extended: Bool, payload: [UInt8],
        file: StaticString = #filePath, line sourceLine: UInt = #line
    ) {
        XCTAssertEqual(
            parser.parse(line),
            .success(ELM327CANFrame(canIdentifier: id, isExtended: extended, payload: payload)),
            file: file, line: sourceLine
        )
    }

    /// 解析結果が期待どおりのエラーであることを確認します。
    ///
    /// 責務: 行を解析し、失敗理由を比較します。
    private func assertError(
        _ line: String, _ error: ELM327CANFrameParseError,
        file: StaticString = #filePath, line sourceLine: UInt = #line
    ) {
        XCTAssertEqual(parser.parse(line), .failure(error), "\(line)", file: file, line: sourceLine)
    }

    /// 3桁IDを11bitとして解析します。
    ///
    /// 責務: 実車形式の行から11bit IDとpayloadが得られることを確認します。
    func testParsesStandardIdentifier() {
        assertFrame("7E8 06 41 00 BE 3F A8 13", id: 0x7E8, extended: false, payload: [0x06, 0x41, 0x00, 0xBE, 0x3F, 0xA8, 0x13])
    }

    /// 8桁IDを29bitとして解析します。
    ///
    /// 責務: 8桁IDが拡張IDになることを確認します。
    func testParsesEightDigitIdentifier() {
        assertFrame("18DAF110 06 41 00", id: 0x18DA_F110, extended: true, payload: [0x06, 0x41, 0x00])
    }

    /// 2桁区切りの29bit IDを解析します。
    ///
    /// 責務: 先頭4トークンが連結されpayloadから除かれることを確認します。
    func testParsesSplitExtendedIdentifier() {
        assertFrame("18 DA F1 10 06 41 00", id: 0x18DA_F110, extended: true, payload: [0x06, 0x41, 0x00])
        assertFrame("18 DA F1 10", id: 0x18DA_F110, extended: true, payload: [])
    }

    /// 小文字・連続空白・プロンプト・前後空白を受理します。
    ///
    /// 責務: 表記ゆれがあっても同じフレームになることを確認します。
    func testToleratesCaseWhitespaceAndPrompt() {
        assertFrame("7e8  06   4a >", id: 0x7E8, extended: false, payload: [0x06, 0x4A])
        assertFrame("  >18daf110 0a\r", id: 0x18DA_F110, extended: true, payload: [0x0A])
    }

    /// 11bit IDの範囲外を拒否します。
    ///
    /// 責務: 3桁で0x7FFを超える値が範囲外エラーになることを確認します。
    func testStandardIdentifierOutOfRange() {
        assertError("800 01", .identifierOutOfRange)
        assertError("FFF 01", .identifierOutOfRange)
        assertFrame("7FF 01", id: 0x7FF, extended: false, payload: [0x01])
        assertFrame("000 01", id: 0, extended: false, payload: [0x01])
    }

    /// 29bit IDの範囲外を拒否します。
    ///
    /// 責務: 8桁で0x1FFFFFFFを超える値が範囲外エラーになることを確認します。
    func testExtendedIdentifierOutOfRange() {
        assertError("20000000 01", .identifierOutOfRange)
        assertFrame("1FFFFFFF 01", id: 0x1FFF_FFFF, extended: true, payload: [0x01])
    }

    /// 2桁区切りIDの失敗を確認します。
    ///
    /// 責務: トークン不足、範囲外、非16進を各エラーに分類することを確認します。
    func testSplitIdentifierFailures() {
        assertError("06 41 00", .missingIdentifier)
        assertError("06", .missingIdentifier)
        assertError("FF DA F1 10", .identifierOutOfRange)
        assertError("18 DA F1 1G 06", .invalidIdentifier)
        assertError("18 DA F1 123 06", .invalidIdentifier)
    }

    /// 不正な桁数や非16進のIDを拒否します。
    ///
    /// 責務: 1・4〜7・9桁以上と非16進が`invalidIdentifier`になることを確認します。
    func testInvalidIdentifierTokens() {
        for token in ["7", "7E8F", "7E8F1", "7E8F11", "7E8F110", "18DAF1100", "7G8", "GGGGGGGG"] {
            assertError("\(token) 01", .invalidIdentifier)
        }
    }

    /// データ長0〜8の11bitフレームを解析します。
    ///
    /// 責務: 11bitで0〜8バイトがすべて成功することを確認します。
    func testStandardPayloadLengths() {
        let bytes: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
        for count in 0...8 {
            let text = bytes.prefix(count).map { String(format: "%02X", $0) }.joined(separator: " ")
            assertFrame("7E8 " + text, id: 0x7E8, extended: false, payload: Array(bytes.prefix(count)))
        }
    }

    /// データ長0〜8の29bitフレームを解析します。
    ///
    /// 責務: 8桁IDで0〜8バイトがすべて成功することを確認します。
    func testExtendedPayloadLengths() {
        let bytes: [UInt8] = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
        for count in 0...8 {
            let text = bytes.prefix(count).map { String(format: "%02X", $0) }.joined(separator: " ")
            assertFrame("18DAF110 " + text, id: 0x18DA_F110, extended: true, payload: Array(bytes.prefix(count)))
        }
    }

    /// 空行を拒否します。
    ///
    /// 責務: 空文字・空白のみ・`>`のみが`emptyLine`になることを確認します。
    func testEmptyLines() {
        assertError("", .emptyLine)
        assertError("   ", .emptyLine)
        assertError(">", .emptyLine)
        assertError(" > \r", .emptyLine)
    }

    /// 不正なデータトークンを拒否します。
    ///
    /// 責務: 桁数違いは`malformedByte`、非16進は`nonHexadecimalByte`になることを確認します。
    func testInvalidDataTokens() {
        assertError("7E8 0", .malformedByte)
        assertError("7E8 064", .malformedByte)
        assertError("7E8 06 4", .malformedByte)
        assertError("7E8 0G", .nonHexadecimalByte)
        assertError("18DAF110 06 ZZ", .nonHexadecimalByte)
    }

    /// 9バイト以上のデータを拒否します。
    ///
    /// 責務: 9・10バイトが`payloadTooLong`になることを確認します。
    func testPayloadTooLong() {
        assertError("7E8 01 02 03 04 05 06 07 08 09", .payloadTooLong)
        assertError("18DAF110 01 02 03 04 05 06 07 08 09 0A", .payloadTooLong)
    }
}
