import Foundation
import XCTest
@testable import ProjectZD8

/// `UserDefaults`によるデフォルトアダプター設定の保存と復元を検証します。
final class UserDefaultsDefaultAdapterPreferenceStoreTests: XCTestCase {
    /// 保存した設定を同じ識別情報で復元できることを検証します。
    ///
    /// 責務: デフォルト設定のプロパティリスト往復が値を維持することを確認します。
    func testSaveAndLoadPreserveDefaultAdapterPreference() throws {
        let suiteName = "UserDefaultsDefaultAdapterPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsDefaultAdapterPreferenceStore(defaults: defaults)
        let preference = DefaultAdapterPreference(
            adapterID: "usb:adapter",
            transportMode: .usb,
            displayName: "ZD8 Adapter",
            systemIdentifier: "/dev/cu.usbserial"
        )

        store.save(preference)

        XCTAssertEqual(store.load(), preference)
    }

    /// 不完全な保存辞書をデフォルト設定として復元しないことを検証します。
    ///
    /// 責務: 必須識別情報が欠けた保存値を未設定として扱うことを確認します。
    func testLoadReturnsNilForIncompleteStoredValue() throws {
        let suiteName = "UserDefaultsDefaultAdapterPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["adapterID": "partial"], forKey: "deviceConnection.defaultAdapter")
        let store = UserDefaultsDefaultAdapterPreferenceStore(defaults: defaults)

        XCTAssertNil(store.load())
    }
}
