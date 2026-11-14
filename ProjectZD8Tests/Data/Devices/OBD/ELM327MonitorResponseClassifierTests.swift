import XCTest
@testable import ProjectZD8

/// ATMA応答行の分類を検証します。
@MainActor
final class ELM327MonitorResponseClassifierTests: XCTestCase {
    /// 検証対象の応答分類器です。
    private let classifier = ELM327MonitorResponseClassifier()
    /// 成功フレームとして解析できる代表行です。
    private let frame = "7E8 06 41 00 BE 3F A8 13"

    /// 6種の結果をそれぞれ確認します。
    ///
    /// 責務: 単独の代表入力が各結果に分類されることを確認します。
    func testEachOutcome() {
        XCTAssertEqual(classifier.classify([frame]), .framesReceived)
        XCTAssertEqual(classifier.classify(["?"]), .unsupported)
        XCTAssertEqual(classifier.classify(["BUFFER FULL"]), .bufferFull)
        XCTAssertEqual(classifier.classify(["NO DATA"]), .silent)
        XCTAssertEqual(classifier.classify(["CAN ERROR"]), .busError)
        XCTAssertEqual(classifier.classify(["STOPPED"]), .stopped)
    }

    /// 無視される入力はsilentになります。
    ///
    /// 責務: 空配列、空行、エコー、SEARCHING、無関係な行だけの場合を確認します。
    func testIgnoredAndUnrecognizedInputIsSilent() {
        XCTAssertEqual(classifier.classify([]), .silent)
        XCTAssertEqual(classifier.classify(["", "  ", ">"]), .silent)
        XCTAssertEqual(classifier.classify(["ATMA"]), .silent)
        XCTAssertEqual(classifier.classify(["SEARCHING..."]), .silent)
        XCTAssertEqual(classifier.classify(["HELLO WORLD", "OK"]), .silent)
    }

    /// SEARCHING行が結果に影響しません。
    ///
    /// 責務: SEARCHING+フレームがframesReceivedになることを確認します。
    func testSearchingLineIsIgnored() {
        XCTAssertEqual(classifier.classify(["SEARCHING...", frame]), .framesReceived)
        XCTAssertEqual(classifier.classify(["ATMA", "SEARCHING...", "NO DATA"]), .silent)
    }

    /// BUFFER FULLが最優先であることを確認します。
    ///
    /// 責務: フレームの前後・CAN ERROR・`?`との同時出現でもbufferFullになることを確認します。
    func testBufferFullHasHighestPriority() {
        XCTAssertEqual(classifier.classify([frame, "BUFFER FULL"]), .bufferFull)
        XCTAssertEqual(classifier.classify(["BUFFER FULL", frame]), .bufferFull)
        XCTAssertEqual(classifier.classify(["BUFFER FULL", "CAN ERROR"]), .bufferFull)
        XCTAssertEqual(classifier.classify(["CAN ERROR", "BUFFER FULL"]), .bufferFull)
        XCTAssertEqual(classifier.classify(["?", "BUFFER FULL"]), .bufferFull)
    }

    /// CAN ERRORの優先順位を確認します。
    ///
    /// 責務: `?`・フレームより優先されることを確認します。
    func testCANErrorPriority() {
        XCTAssertEqual(classifier.classify(["CAN ERROR", "?"]), .busError)
        XCTAssertEqual(classifier.classify(["?", "CAN ERROR"]), .busError)
        XCTAssertEqual(classifier.classify([frame, "CAN ERROR"]), .busError)
        XCTAssertEqual(classifier.classify(["CAN ERROR", frame]), .busError)
    }

    /// `?`の優先順位を確認します。
    ///
    /// 責務: フレームより優先され、行全体が`?`の時だけ成立することを確認します。
    func testQuestionMarkPriorityAndExactness() {
        XCTAssertEqual(classifier.classify([frame, "?"]), .unsupported)
        XCTAssertEqual(classifier.classify(["?", frame]), .unsupported)
        XCTAssertEqual(classifier.classify(["WHAT?"]), .silent)
        XCTAssertEqual(classifier.classify(["? ?"]), .silent)
    }

    /// STOPPEDとNO DATAの優先順位を確認します。
    ///
    /// 責務: フレームがSTOPPEDに勝ち、STOPPEDがNO DATAに勝つことを確認します。
    func testStoppedPriority() {
        XCTAssertEqual(classifier.classify([frame, "STOPPED"]), .framesReceived)
        XCTAssertEqual(classifier.classify(["STOPPED", "NO DATA"]), .stopped)
        XCTAssertEqual(classifier.classify(["NO DATA", "STOPPED"]), .stopped)
        XCTAssertEqual(classifier.classify([frame, "NO DATA"]), .framesReceived)
    }

    /// 表記ゆれを受理します。
    ///
    /// 責務: 小文字・前後空白・`>`付きの行も同様に分類されることを確認します。
    func testCaseWhitespaceAndPromptTolerance() {
        XCTAssertEqual(classifier.classify(["  buffer full  "]), .bufferFull)
        XCTAssertEqual(classifier.classify(["can error>"]), .busError)
        XCTAssertEqual(classifier.classify([">stopped"]), .stopped)
        XCTAssertEqual(classifier.classify([" no data >"]), .silent)
        XCTAssertEqual(classifier.classify(["> ?"]), .unsupported)
        XCTAssertEqual(classifier.classify(["7e8 06 41 00 be >"]), .framesReceived)
        XCTAssertEqual(classifier.classify(["searching..."]), .silent)
        XCTAssertEqual(classifier.classify(["atma", "7e8 01 02"]), .framesReceived)
    }

    /// キーワードの部分一致を確認します。
    ///
    /// 責務: 行の一部にキーワードがあれば成立することを確認します。
    func testKeywordsMatchBySubstring() {
        XCTAssertEqual(classifier.classify(["<BUFFER FULL>"]), .bufferFull)
        XCTAssertEqual(classifier.classify(["FB ERROR CAN ERROR"]), .busError)
        XCTAssertEqual(classifier.classify(["MONITOR STOPPED NOW"]), .stopped)
    }
}
