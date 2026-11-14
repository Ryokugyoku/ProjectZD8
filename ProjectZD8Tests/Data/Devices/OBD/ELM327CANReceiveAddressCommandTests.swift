import XCTest
@testable import ProjectZD8

/// ATCRAコマンドの生成を検証します。
@MainActor
final class ELM327CANReceiveAddressCommandTests: XCTestCase {
    /// 11bit IDのコマンドを確認します。
    ///
    /// 責務: 0x7E8が`ATCRA7E8`、0x012が3桁ゼロ埋めの`ATCRA012`になることを確認します。
    func testStandardIdentifier() throws {
        let command = try XCTUnwrap(ELM327CANReceiveAddressCommand(identifier: 0x7E8))
        XCTAssertEqual(command.requestID, "ATCRA7E8")
        XCTAssertEqual(command.encodedData, Data("ATCRA7E8\r".utf8))
        XCTAssertEqual(ELM327CANReceiveAddressCommand(identifier: 0x012)?.requestID, "ATCRA012")
    }

    /// 29bit IDのコマンドを確認します。
    ///
    /// 責務: 0x18DAF110が8桁の`ATCRA18DAF110`になることを確認します。
    func testExtendedIdentifier() throws {
        let command = try XCTUnwrap(ELM327CANReceiveAddressCommand(identifier: 0x18DA_F110))
        XCTAssertEqual(command.requestID, "ATCRA18DAF110")
        XCTAssertEqual(command.encodedData, Data("ATCRA18DAF110\r".utf8))
    }

    /// 幅の境界を確認します。
    ///
    /// 責務: 0x800が8桁、0x1FFFFFFFが成功、0x20000000がnilになることを確認します。
    func testBoundaries() {
        XCTAssertEqual(ELM327CANReceiveAddressCommand(identifier: 0x800)?.requestID, "ATCRA00000800")
        XCTAssertEqual(ELM327CANReceiveAddressCommand(identifier: 0x1FFF_FFFF)?.requestID, "ATCRA1FFFFFFF")
        XCTAssertNil(ELM327CANReceiveAddressCommand(identifier: 0x2000_0000))
    }
}
