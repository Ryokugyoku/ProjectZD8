import XCTest
@testable import ProjectZD8

/// ホームの車両表示の文言キーの規則を検証します。
@MainActor
final class HomeVehicleLabelTests: XCTestCase {
    /// 未登録は未登録の文言キーです。
    ///
    /// 責務: unregistered の `localizationKey` を確かめます。
    func testUnregisteredKey() {
        XCTAssertEqual(HomeVehicleLabel.unregistered.localizationKey, "home.vehicle.unregistered")
    }

    /// 名前なしは名前なしの文言キーです。
    ///
    /// 責務: unnamed の `localizationKey` を確かめます。
    func testUnnamedKey() {
        XCTAssertEqual(HomeVehicleLabel.unnamed.localizationKey, "home.vehicle.unnamed")
    }

    /// 名前ありは名前をそのまま出すので文言キーを持ちません。
    ///
    /// 責務: named の `localizationKey` が nil であることを確かめます。
    func testNamedHasNoKey() {
        XCTAssertNil(HomeVehicleLabel.named("BRZ").localizationKey)
        XCTAssertNil(HomeVehicleLabel.named("home.vehicle.unnamed").localizationKey)
    }
}
