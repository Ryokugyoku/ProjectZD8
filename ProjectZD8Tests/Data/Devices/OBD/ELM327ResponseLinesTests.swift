import XCTest
@testable import ProjectZD8

/// `ELM327ResponseLines` の行分割・正規化と、拒否(`?`)の判定を検証します。
final class ELM327ResponseLinesTests: XCTestCase {
    /// `\r`・`\n`・`\r\n` のどれでも行に分かれ、空行は除かれます。
    ///
    /// 責務: 改行コードの違いで行の結果が変わらないことを確認します。
    func testSplitsOnEveryLineBreakAndDropsEmptyLines() {
        let expected = ["SEARCHING...", "41 00 BE 3E B8 13"]
        XCTAssertEqual(ELM327ResponseLines.normalizedLines(of: "SEARCHING...\r41 00 BE 3E B8 13\r\r>"), expected)
        XCTAssertEqual(ELM327ResponseLines.normalizedLines(of: "SEARCHING...\n41 00 BE 3E B8 13\n\n>"), expected)
        XCTAssertEqual(ELM327ResponseLines.normalizedLines(of: "SEARCHING...\r\n41 00 BE 3E B8 13\r\n>"), expected)
    }

    /// プロンプト `>` を除き、前後の空白を除き、大文字にします。行内の空白は残します。
    ///
    /// 責務: 1行の正規化の内容を確認します。
    func testNormalizesPromptWhitespaceAndCase() {
        XCTAssertEqual(ELM327ResponseLines.normalizedLines(of: "  elm327 v1.5 \t>"), ["ELM327 V1.5"])
        XCTAssertEqual(ELM327ResponseLines.normalizedLines(of: ">41 00 be"), ["41 00 BE"])
    }

    /// 空・プロンプトだけ・空白と改行だけの応答は行を持ちません。
    ///
    /// 責務: 内容の無い応答の境界を確認します。
    func testEmptyResponsesHaveNoLines() {
        for response in ["", ">", "\r\r>", "  \r \n\t", " > "] {
            XCTAssertEqual(ELM327ResponseLines.normalizedLines(of: response), [], response.debugDescription)
        }
    }

    /// `?` だけの行があれば拒否です(前後の空白・プロンプト・他の行があっても)。
    ///
    /// 責務: 拒否と判定される形を確認します。
    func testQuestionMarkLineIsRejection() {
        for response in ["?", "?\r\r>", " ? \r>", "ATXX\r?\r>"] {
            XCTAssertTrue(ELM327ResponseLines.isRejection(response), response.debugDescription)
        }
    }

    /// `?` を含んでも `?` だけの行でなければ拒否ではありません。正常応答・空応答も拒否ではありません。
    ///
    /// 責務: 拒否と判定されない形を確認します。
    func testOtherResponsesAreNotRejection() {
        for response in ["OK\r\r>", "?? \r>", "WHAT?\r>", "41 00 BE 3E B8 13\r>", "", ">"] {
            XCTAssertFalse(ELM327ResponseLines.isRejection(response), response.debugDescription)
        }
    }
}
