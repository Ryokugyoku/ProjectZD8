import XCTest
@testable import ProjectZD8

/// STFAPコマンドの生成を検証します。
@MainActor
final class STNPassFilterCommandTests: XCTestCase {
    /// 11bitのパスフィルターを確認します。
    ///
    /// 責務: (0x7E8, 0x7FF)が`STFAP7E8,7FF`になることを確認します。
    func testStandardFilter() throws {
        let command = try XCTUnwrap(STNPassFilterCommand(pattern: 0x7E8, mask: 0x7FF, isExtended: false))
        XCTAssertEqual(command.requestID, "STFAP7E8,7FF")
        XCTAssertEqual(command.encodedData, Data("STFAP7E8,7FF\r".utf8))
    }

    /// 29bitのパスフィルターを確認します。
    ///
    /// 責務: (0x18DAF110, 0x1FFFFFFF)が`STFAP18DAF110,1FFFFFFF`になることを確認します。
    func testExtendedFilter() throws {
        let command = try XCTUnwrap(STNPassFilterCommand(pattern: 0x18DA_F110, mask: 0x1FFF_FFFF, isExtended: true))
        XCTAssertEqual(command.requestID, "STFAP18DAF110,1FFFFFFF")
    }

    /// パターンまたはマスクが幅を超えると拒否します。
    ///
    /// 責務: どちらか一方でも幅外ならnilになることを確認します。
    func testRejectsValuesExceedingWidth() {
        XCTAssertNil(STNPassFilterCommand(pattern: 0x800, mask: 0x7FF, isExtended: false))
        XCTAssertNil(STNPassFilterCommand(pattern: 0x7E8, mask: 0x800, isExtended: false))
        XCTAssertNil(STNPassFilterCommand(pattern: 0x2000_0000, mask: 0x1FFF_FFFF, isExtended: true))
        XCTAssertNil(STNPassFilterCommand(pattern: 0x18DA_F110, mask: 0x2000_0000, isExtended: true))
    }
}
