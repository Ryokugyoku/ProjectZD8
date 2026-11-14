import XCTest
@testable import ProjectZD8

/// ATCFコマンドの生成を検証します。
@MainActor
final class ELM327CANFilterCommandTests: XCTestCase {
    /// ID値から幅を決める初期化を確認します。
    ///
    /// 責務: 0x7E8が`ATCF7E8`、0x18DAF110が`ATCF18DAF110`、範囲外がnilになることを確認します。
    func testInitFromIdentifier() throws {
        let standard = try XCTUnwrap(ELM327CANFilterCommand(identifier: 0x7E8))
        XCTAssertEqual(standard.requestID, "ATCF7E8")
        XCTAssertEqual(standard.encodedData, Data("ATCF7E8\r".utf8))
        XCTAssertEqual(ELM327CANFilterCommand(identifier: 0x18DA_F110)?.requestID, "ATCF18DAF110")
        XCTAssertNil(ELM327CANFilterCommand(identifier: 0x2000_0000))
    }

    /// 幅を明示する初期化の桁数を確認します。
    ///
    /// 責務: 指定した幅の桁数でゼロ埋めされることを確認します。
    func testInitWithExplicitWidth() {
        XCTAssertEqual(ELM327CANFilterCommand(identifier: 0x7E8, isExtended: true)?.requestID, "ATCF000007E8")
        XCTAssertEqual(ELM327CANFilterCommand(identifier: 0x7E8, isExtended: false)?.requestID, "ATCF7E8")
        XCTAssertEqual(ELM327CANFilterCommand(identifier: 0x7FF, isExtended: false)?.requestID, "ATCF7FF")
        XCTAssertEqual(ELM327CANFilterCommand(identifier: 0x1FFF_FFFF, isExtended: true)?.requestID, "ATCF1FFFFFFF")
    }

    /// 幅を超える値を拒否します。
    ///
    /// 責務: 指定幅に収まらない値がnilになることを確認します。
    func testRejectsValueExceedingWidth() {
        XCTAssertNil(ELM327CANFilterCommand(identifier: 0x800, isExtended: false))
        XCTAssertNil(ELM327CANFilterCommand(identifier: 0x2000_0000, isExtended: true))
    }
}
