import Foundation
import XCTest
@testable import ProjectZD8

/// `ELM327AdaptiveTimingCommand` の要求IDと送信バイト列を検証します。
///
/// 仕様: U3 受け入れ条件 9(抑止中の見張りでは `ATAT0` で適応タイミングを切る)。
final class ELM327AdaptiveTimingCommandTests: XCTestCase {
    /// 適応タイミングを切るコマンドは `ATAT0` で、CR 終端で送ります。
    ///
    /// 責務: `off` のモード・要求ID・送信バイト列を確認します。
    func testOffIsATAT0() {
        XCTAssertEqual(ELM327AdaptiveTimingCommand.off.mode, 0)
        XCTAssertEqual(ELM327AdaptiveTimingCommand.off.requestID, "ATAT0")
        XCTAssertEqual(ELM327AdaptiveTimingCommand.off.encodedData, Data("ATAT0\r".utf8))
    }

    /// 他のモードでは、そのモードの数字が要求IDと送信バイト列に入ります。
    ///
    /// 責務: モード1・2の要求ID・送信バイト列を確認します。
    func testOtherModesEncodeTheirNumber() {
        for mode: UInt8 in [1, 2] {
            let command = ELM327AdaptiveTimingCommand(mode: mode)
            XCTAssertEqual(command.requestID, "ATAT\(mode)")
            XCTAssertEqual(command.encodedData, Data("ATAT\(mode)\r".utf8))
        }
    }
}
