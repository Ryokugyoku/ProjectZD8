import XCTest
@testable import ProjectZD8

/// ATCMコマンドの生成を検証します。
@MainActor
final class ELM327CANMaskCommandTests: XCTestCase {
    /// 11bitマスクを確認します。
    ///
    /// 責務: 0x7FEが`ATCM7FE`、0x7FFが`ATCM7FF`、0が`ATCM000`になることを確認します。
    func testStandardMask() throws {
        let command = try XCTUnwrap(ELM327CANMaskCommand(mask: 0x7FE, isExtended: false))
        XCTAssertEqual(command.requestID, "ATCM7FE")
        XCTAssertEqual(command.encodedData, Data("ATCM7FE\r".utf8))
        XCTAssertEqual(ELM327CANMaskCommand(mask: 0x7FF, isExtended: false)?.requestID, "ATCM7FF")
        XCTAssertEqual(ELM327CANMaskCommand(mask: 0, isExtended: false)?.requestID, "ATCM000")
    }

    /// 29bitマスクを確認します。
    ///
    /// 責務: 0x1FFFFFFEが`ATCM1FFFFFFE`、小さい値は8桁ゼロ埋めになることを確認します。
    func testExtendedMask() throws {
        let command = try XCTUnwrap(ELM327CANMaskCommand(mask: 0x1FFF_FFFE, isExtended: true))
        XCTAssertEqual(command.requestID, "ATCM1FFFFFFE")
        XCTAssertEqual(ELM327CANMaskCommand(mask: 0x7FE, isExtended: true)?.requestID, "ATCM000007FE")
    }

    /// 幅を超えるマスクを拒否します。
    ///
    /// 責務: 11bitで0x800、29bitで0x20000000がnilになることを確認します。
    func testRejectsMaskExceedingWidth() {
        XCTAssertNil(ELM327CANMaskCommand(mask: 0x800, isExtended: false))
        XCTAssertNil(ELM327CANMaskCommand(mask: 0x2000_0000, isExtended: true))
    }
}
