import XCTest
@testable import ProjectZD8

/// ELM327のPID応答の分類を検証します。
final class ELM327ResponseParserTests: XCTestCase {
    private let rpm = OBDPIDRequest(service: 0x01, pid: 0x0C)

    /// 責務: 空白区切りの正応答からサービスとPIDのエコーを除いたデータを取り出すことを確認します。
    func testExtractsPayloadAfterEcho() {
        XCTAssertEqual(ELM327ResponseParser().parse("41 0C 1A F8", request: rpm), .data([0x1A, 0xF8]))
    }

    /// 責務: SEARCHING行を無視して正応答を取り出せることを確認します。
    func testIgnoresSearchingLine() {
        XCTAssertEqual(ELM327ResponseParser().parse("SEARCHING...\r41 0C 0B B8\r", request: rpm), .data([0x0B, 0xB8]))
    }

    /// 責務: サービス21の正応答(61)も同じ規則で取り出せることを確認します。
    func testExtractsServiceTwentyOneResponse() {
        let request = OBDPIDRequest(service: 0x21, pid: 0x17)
        XCTAssertEqual(ELM327ResponseParser().parse("61 17 7B", request: request), .data([0x7B]))
    }

    /// 責務: NO DATAがデータ無しへ分類されることを確認します。
    func testClassifiesNoData() {
        XCTAssertEqual(ELM327ResponseParser().parse("NO DATA", request: rpm), .noData)
    }

    /// 責務: エラー応答が拒否へ分類されることを確認します。
    func testClassifiesAdapterErrorsAsRejected() {
        for text in ["?", "UNABLE TO CONNECT", "BUS ERROR", "CAN ERROR", "STOPPED"] {
            XCTAssertEqual(ELM327ResponseParser().parse(text, request: rpm), .rejected, text)
        }
    }

    /// 責務: 別PIDの正応答が遅延応答として区別されることを確認します。
    func testClassifiesOtherPositiveResponse() {
        XCTAssertEqual(ELM327ResponseParser().parse("41 0D 32", request: rpm), .otherResponse)
    }

    /// 責務: ペイロードが空、または16進として読めない応答を未解釈とすることを確認します。
    func testClassifiesEmptyPayloadAndGarbageAsUnrecognized() {
        XCTAssertEqual(ELM327ResponseParser().parse("41 0C", request: rpm), .unrecognized)
        XCTAssertEqual(ELM327ResponseParser().parse("garbage", request: rpm), .unrecognized)
        XCTAssertEqual(ELM327ResponseParser().parse("", request: rpm), .unrecognized)
    }
}
