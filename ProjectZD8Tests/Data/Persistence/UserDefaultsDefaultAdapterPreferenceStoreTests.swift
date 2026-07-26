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

    /// 物理終端を持たない旧保存形式を探索方式から安全に補完できることを検証します。
    ///
    /// 責務: 旧形式のUSB設定をシリアル終端として後方互換復元することを確認します。
    func testLoadRestoresLegacyUSBPreferenceAsSerialTransport() throws {
        let suiteName = "UserDefaultsDefaultAdapterPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            [
                "adapterID": "usb:legacy",
                "transportMode": AdapterTransportMode.usb.rawValue,
                "displayName": "Legacy USB",
                "systemIdentifier": "/dev/cu.legacy"
            ],
            forKey: "deviceConnection.defaultAdapter"
        )
        let store = UserDefaultsDefaultAdapterPreferenceStore(defaults: defaults)

        XCTAssertEqual(store.load()?.connectionTransport, .serial)
    }

    /// 物理終端を持たない旧Bluetooth形式を識別子からClassicとして補完できることを検証します。
    ///
    /// 責務: UUIDではない旧Bluetooth設定をExternal Accessory向けClassic終端として復元することを確認します。
    func testLoadRestoresLegacyNonUUIDBluetoothPreferenceAsClassicTransport() throws {
        let suiteName = "UserDefaultsDefaultAdapterPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            [
                "adapterID": "bluetooth:legacy-classic",
                "transportMode": AdapterTransportMode.bluetooth.rawValue,
                "displayName": "Legacy Classic",
                "systemIdentifier": "42"
            ],
            forKey: "deviceConnection.defaultAdapter"
        )
        let store = UserDefaultsDefaultAdapterPreferenceStore(defaults: defaults)

        XCTAssertEqual(store.load()?.connectionTransport, .bluetoothClassic)
    }

    /// アカウント削除時に保存済みデフォルトアダプターを除去できることを検証します。
    ///
    /// 責務: 端末固有設定の削除後にデフォルトアダプターが復元されないことを確認します。
    func testRemoveDeletesSavedDefaultAdapterPreference() throws {
        let suiteName = "UserDefaultsDefaultAdapterPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsDefaultAdapterPreferenceStore(defaults: defaults)
        store.save(
            DefaultAdapterPreference(
                adapterID: "bluetooth:adapter",
                transportMode: .bluetooth,
                displayName: "ZD8 Adapter",
                systemIdentifier: "adapter-id"
            )
        )

        store.remove()

        XCTAssertNil(store.load())
    }
}
