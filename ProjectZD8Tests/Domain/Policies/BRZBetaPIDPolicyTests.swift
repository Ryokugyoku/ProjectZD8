import XCTest
@testable import ProjectZD8

/// BRZ BetaのPID選択条件を検証します。
final class BRZBetaPIDPolicyTests: XCTestCase {
    /// 対応済み回転数と車速だけを固定順で選択します。
    ///
    /// 責務: 2件が揃った定義一覧をBeta対象へ変換できることを確認します。
    func testSelectsEngineAndVehicleSpeedWhenBothAreSupported() {
        let selected = BRZBetaPIDPolicy().definitions(from: [definition(pid: 0x0D), definition(pid: 0x05), definition(pid: 0x0C)])

        XCTAssertEqual(selected?.map(\.pid), [0x0C, 0x0D])
    }

    /// 必須PIDが欠ける場合はBetaを選択しません。
    ///
    /// 責務: 対応確認できないPIDを周期送信対象へ推測追加しないことを確認します。
    func testRejectsDefinitionsMissingEitherRequiredPID() {
        XCTAssertNil(BRZBetaPIDPolicy().definitions(from: [definition(pid: 0x0C)]))
    }

    /// 指定PIDの数値化可能なテスト定義を生成します。
    ///
    /// 責務: 1件のPID番号を選択方針テスト用定義へ変換します。
    /// - Parameter pid: 定義へ設定するService 01 PID番号。
    /// - Returns: 1バイト式を持つテスト定義。
    private func definition(pid: UInt8) -> OBDPIDDefinition {
        OBDPIDDefinition(
            service: 0x01,
            pid: pid,
            nameKey: "test.pid",
            requiredByteCount: 1,
            formula: "A",
            unit: "",
            minimumValue: nil,
            maximumValue: nil,
            sourceURI: "test://brz-beta",
            revision: 1
        )
    }
}
