import XCTest
@testable import ProjectZD8

/// 未登録車両の警告の主要操作 `UnassignedObservedVINWarningPrimaryAction` の表示値を検証します。
@MainActor
final class UnassignedObservedVINWarningPrimaryActionTests: XCTestCase {
    /// 登録と再読込のボタン名キーは空でなく、互いに異なります。
    ///
    /// 責務: `titleKey` の両分岐が別々の文言を指すことを確認します。
    func testTitleKeysAreDistinct() {
        let register = UnassignedObservedVINWarningPrimaryAction.registerVehicle(vin: "JF1ZD8A11P9000001").titleKey
        let retry = UnassignedObservedVINWarningPrimaryAction.retryLoading.titleKey
        XCTAssertFalse(register.isEmpty)
        XCTAssertFalse(retry.isEmpty)
        XCTAssertNotEqual(register, retry)
    }

    /// 登録のボタン名はVINに左右されません。
    ///
    /// 責務: 異なるVINでも同じ `titleKey` を返すことを確認します。
    func testRegisterTitleKeyDoesNotDependOnVIN() {
        XCTAssertEqual(
            UnassignedObservedVINWarningPrimaryAction.registerVehicle(vin: "A").titleKey,
            UnassignedObservedVINWarningPrimaryAction.registerVehicle(vin: "B").titleKey
        )
    }

    /// 両方の操作のアイコン名は空ではありません。
    ///
    /// 責務: `systemImageName` の両分岐が描画できる名前を返すことを確認します。
    func testSystemImageNamesAreNotEmpty() {
        XCTAssertFalse(UnassignedObservedVINWarningPrimaryAction.registerVehicle(vin: "A").systemImageName.isEmpty)
        XCTAssertFalse(UnassignedObservedVINWarningPrimaryAction.retryLoading.systemImageName.isEmpty)
    }
}
