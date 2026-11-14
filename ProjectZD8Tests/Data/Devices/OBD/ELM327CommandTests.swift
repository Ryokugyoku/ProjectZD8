import XCTest
@testable import ProjectZD8

/// 段階2で追加したELM/STNコマンドcaseの送信文字列を検証します。
@MainActor
final class ELM327CommandTests: XCTestCase {
    /// 追加5 caseの送信データを確認します。
    ///
    /// 責務: 各caseの`encodedData`が「コマンド文字列+復帰文字」のUTF-8であることを確認します。
    func testEncodedDataOfAddedCases() {
        let expected: [(ELM327Command, String)] = [
            (.stnIdentity, "STI\r"),
            (.monitorAll, "ATMA\r"),
            (.headersOn, "ATH1\r"),
            (.stnMonitor, "STM\r"),
            (.programmableParameterSummary, "ATPPS\r")
        ]
        for (command, text) in expected {
            XCTAssertEqual(command.encodedData, Data(text.utf8), "\(command)")
        }
    }

    /// 追加5 caseの要求識別子を確認します。
    ///
    /// 責務: `requestID`がcase名と一致することを確認します。
    func testRequestIDOfAddedCasesIsCaseName() {
        XCTAssertEqual(ELM327Command.stnIdentity.requestID, "stnIdentity")
        XCTAssertEqual(ELM327Command.monitorAll.requestID, "monitorAll")
        XCTAssertEqual(ELM327Command.headersOn.requestID, "headersOn")
        XCTAssertEqual(ELM327Command.stnMonitor.requestID, "stnMonitor")
        XCTAssertEqual(ELM327Command.programmableParameterSummary.requestID, "programmableParameterSummary")
    }
}
