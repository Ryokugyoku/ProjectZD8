import XCTest
@testable import ProjectZD8

/// `UserDefaultsDefaultAdapterStore` の保存・解除・破損データ処理を検証します。
final class UserDefaultsDefaultAdapterStoreTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "test.adapter.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// 責務: 未設定は `nil` で、保存した値が往復し、`nil` 保存で解除されることを確認します。
    func testSaveLoadAndClear() throws {
        let store = UserDefaultsDefaultAdapterStore(defaults: try makeDefaults())
        XCTAssertNil(store.load())
        let adapter = AdapterDescriptor(transport: .usbSerial, systemIdentifier: "/dev/cu.x", displayName: "OBDLink", detail: "MX")
        store.save(adapter)
        XCTAssertEqual(store.load(), adapter)
        store.save(nil)
        XCTAssertNil(store.load())
    }

    /// 責務: 復元できない保存データが `nil` として扱われることを確認します。
    func testUndecodableDataReturnsNil() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("{broken".utf8), forKey: UserDefaultsDefaultAdapterStore.key)
        XCTAssertNil(UserDefaultsDefaultAdapterStore(defaults: defaults).load())
    }
}
