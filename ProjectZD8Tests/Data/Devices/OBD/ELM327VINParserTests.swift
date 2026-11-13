import XCTest
@testable import ProjectZD8

/// Service 09 PID 02のVIN復元を検証します。
final class ELM327VINParserTests: XCTestCase {
    /// 責務: CAN自動整形式の連番フレームから17文字VINを復元することを確認します。
    func testParsesCANFormattedVIN() {
        let response = """
        014\r
        0: 49 02 01 31 44 34\r
        1: 47 50 30 30 52 35 35\r
        2: 42 31 32 33 34 35 36\r
        """
        XCTAssertEqual(ELM327VINParser().parse(response), "1D4GP00R55B123456")
    }

    /// 責務: 空白埋めの非VIN識別子をVINとして扱わないことを確認します。
    func testRejectsSpacePaddedIdentifier() {
        let response = """
        014\r
        0: 49 02 01 20 20 20\r
        1: 20 20 20 20 5A 44 38\r
        2: 31 32 33 34 35 36 37\r
        """
        XCTAssertNil(ELM327VINParser().parse(response))
    }

    /// 責務: J1850の行番号形式からVINを復元することを確認します。
    func testParsesLegacyVINFrames() {
        let response = """
        49 02 01 31 44 34 47\r
        49 02 02 50 30 30 52\r
        49 02 03 35 35 42 31\r
        49 02 04 32 33 34 35\r
        49 02 05 36\r
        """
        XCTAssertEqual(ELM327VINParser().parse(response), "1D4GP00R55B123456")
    }

    /// 責務: 17バイト未満の応答やエラー応答をVINとして扱わないことを確認します。
    func testRejectsTruncatedAndErrorResponses() {
        XCTAssertNil(ELM327VINParser().parse("49 02 01 31 32 33"))
        XCTAssertNil(ELM327VINParser().parse("NO DATA"))
        XCTAssertNil(ELM327VINParser().parse("?"))
    }
}
