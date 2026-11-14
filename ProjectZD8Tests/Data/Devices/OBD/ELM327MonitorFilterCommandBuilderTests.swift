import XCTest
@testable import ProjectZD8

/// 受信監視フィルターのコマンド列生成を検証します。
@MainActor
final class ELM327MonitorFilterCommandBuilderTests: XCTestCase {
    /// 検証対象のコマンド列ビルダーです。
    private let builder = ELM327MonitorFilterCommandBuilder()

    /// 生成結果のrequestID配列を返します。
    ///
    /// 責務: 成功時はrequestIDとencodedDataの整合も確認したうえで要求IDを返します。
    private func requestIDs(_ ids: Set<UInt32>, _ chip: OBDAdapterChipFamily) -> [String]? {
        guard case .success(let commands) = builder.commands(for: ids, chipFamily: chip) else { return nil }
        for command in commands {
            XCTAssertEqual(command.encodedData, Data((command.requestID + "\r").utf8))
        }
        return commands.map(\.requestID)
    }

    /// 生成結果のエラーを返します。
    ///
    /// 責務: 失敗時のエラーを取り出します。
    private func failure(_ ids: Set<UInt32>, _ chip: OBDAdapterChipFamily) -> ELM327MonitorFilterCommandBuildError? {
        guard case .failure(let error) = builder.commands(for: ids, chipFamily: chip) else { return nil }
        return error
    }

    /// ELM327の1件指定を確認します。
    ///
    /// 責務: 純正・クローンとも1件なら`ATCRA`1つになることを確認します。
    func testELM327SingleIdentifier() {
        for chip in [OBDAdapterChipFamily.elm327Genuine, .elm327Clone] {
            XCTAssertEqual(requestIDs([0x7E8], chip), ["ATCRA7E8"])
            XCTAssertEqual(requestIDs([0x18DA_F110], chip), ["ATCRA18DAF110"])
        }
    }

    /// ELM327の複数件指定でフィルターとマスクを確認します。
    ///
    /// 責務: 手計算した11bitの期待値と一致することを確認します。
    func testELM327MultipleStandardIdentifiers() {
        for chip in [OBDAdapterChipFamily.elm327Genuine, .elm327Clone] {
            XCTAssertEqual(requestIDs([0x7E8, 0x7E9], chip), ["ATCF7E8", "ATCM7FE"])
            XCTAssertEqual(requestIDs([0x7E8, 0x7EA, 0x7EB], chip), ["ATCF7E8", "ATCM7FC"])
            XCTAssertEqual(requestIDs([0x100, 0x7FF], chip), ["ATCF100", "ATCM100"])
        }
    }

    /// ELM327の29bit複数件指定を確認します。
    ///
    /// 責務: 手計算した29bitの期待値と一致することを確認します。
    func testELM327MultipleExtendedIdentifiers() {
        XCTAssertEqual(
            requestIDs([0x18DA_F110, 0x18DA_F111], .elm327Genuine),
            ["ATCF18DAF110", "ATCM1FFFFFFE"]
        )
    }

    /// 29bitで幅いっぱいの8桁出力になることを確認します。
    ///
    /// 責務: マスク適用後のfilterが小さい値(0)でも8桁ゼロ埋めで出力されることを確認します。
    func testELM327ExtendedFilterIsZeroPaddedToEightDigits() {
        XCTAssertEqual(requestIDs([0x800, 0x1000], .elm327Genuine), ["ATCF00000000", "ATCM1FFFE7FF"])
    }

    /// STN系はID昇順のSTFAPになります。
    ///
    /// 責務: 1件・複数件・29bitの期待値を確認します。
    func testSTNCommands() {
        XCTAssertEqual(requestIDs([0x7E9, 0x7E8], .stn), ["STFAP7E8,7FF", "STFAP7E9,7FF"])
        XCTAssertEqual(requestIDs([0x7E8], .stn), ["STFAP7E8,7FF"])
        XCTAssertEqual(requestIDs([0x18DA_F110], .stn), ["STFAP18DAF110,1FFFFFFF"])
    }

    /// 検証エラーを確認します。
    ///
    /// 責務: 空集合・範囲外・幅の混在が各チップで対応するエラーになることを確認します。
    func testValidationErrors() {
        XCTAssertEqual(failure([], .stn), .emptyIdentifiers)
        XCTAssertEqual(failure([0x2000_0000], .stn), .identifierOutOfRange)
        XCTAssertEqual(failure([0x7E8, 0x2000_0000], .elm327Clone), .identifierOutOfRange)
        XCTAssertEqual(failure([0x7E8, 0x18DA_F110], .stn), .mixedIdentifierWidths)
        XCTAssertEqual(failure([0x7FF, 0x800], .elm327Genuine), .mixedIdentifierWidths)
    }

    /// チップ不明は検証後に拒否します。
    ///
    /// 責務: unknownは不正入力なら入力エラーを優先し、正常入力なら`unsupportedChipFamily`になることを確認します。
    func testUnknownChipFamily() {
        XCTAssertEqual(failure([0x7E8], .unknown), .unsupportedChipFamily)
        XCTAssertEqual(failure([0x7E8, 0x7E9], .unknown), .unsupportedChipFamily)
        XCTAssertEqual(failure([], .unknown), .emptyIdentifiers)
        XCTAssertEqual(failure([0x2000_0000], .unknown), .identifierOutOfRange)
        XCTAssertEqual(failure([0x7E8, 0x18DA_F110], .unknown), .mixedIdentifierWidths)
    }
}
