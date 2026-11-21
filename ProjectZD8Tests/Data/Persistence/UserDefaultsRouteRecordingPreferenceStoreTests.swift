import Foundation
import XCTest
@testable import ProjectZD8

/// `UserDefaultsRouteRecordingPreferenceStore` の既定値・保存・キーの分離を検証します。
@MainActor
final class UserDefaultsRouteRecordingPreferenceStoreTests: XCTestCase {
    /// このテストが作った UserDefaults スイート名です。終了時に消します。
    private var suiteNames: [String] = []

    /// テストで作ったスイートを消します。
    ///
    /// 責務: 作ったスイートの永続領域を削除し、実環境へ設定を残しません。
    override func tearDown() {
        for name in suiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        suiteNames = []
        super.tearDown()
    }

    /// 専用の空スイートを作ります。
    ///
    /// 責務: 一意な名前のスイートを作り、終了時の削除対象に登録します。
    private func makeSuite() throws -> UserDefaults {
        let name = "UserDefaultsRouteRecordingPreferenceStoreTests.\(UUID().uuidString)"
        suiteNames.append(name)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 未保存ならオフです。
    ///
    /// 責務: 空のスイートで `load()` が `false` を返すことを確認します。
    func testLoadIsFalseWhenUnset() throws {
        XCTAssertFalse(UserDefaultsRouteRecordingPreferenceStore(defaults: try makeSuite()).load())
    }

    /// 保存したオン・オフが読め、同じスイートの別インスタンスからも読めます。
    ///
    /// 責務: true→false の順に保存して確認します。
    func testSavedValueIsLoaded() throws {
        let defaults = try makeSuite()
        let store = UserDefaultsRouteRecordingPreferenceStore(defaults: defaults)

        store.save(true)
        XCTAssertTrue(store.load())
        XCTAssertTrue(UserDefaultsRouteRecordingPreferenceStore(defaults: defaults).load())

        store.save(false)
        XCTAssertFalse(store.load())
        XCTAssertFalse(UserDefaultsRouteRecordingPreferenceStore(defaults: defaults).load())
    }

    /// 既定のキーは `logging.routeRecordingEnabled` です。
    ///
    /// 責務: 既定のキーで保存すると、その UserDefaults の当該キーに値が入ることを確認します。
    func testDefaultKeyIsLoggingRouteRecordingEnabled() throws {
        let defaults = try makeSuite()
        UserDefaultsRouteRecordingPreferenceStore(defaults: defaults).save(true)

        XCTAssertEqual(defaults.object(forKey: "logging.routeRecordingEnabled") as? Bool, true)
    }

    /// 別のキーを指定したインスタンスとは値が混ざりません。
    ///
    /// 責務: 同じスイートでキーだけ違う2つのストアが独立していることを確認します。
    func testDifferentKeysDoNotShareValues() throws {
        let defaults = try makeSuite()
        let first = UserDefaultsRouteRecordingPreferenceStore(defaults: defaults, key: "test.first")
        let second = UserDefaultsRouteRecordingPreferenceStore(defaults: defaults, key: "test.second")

        first.save(true)

        XCTAssertTrue(first.load())
        XCTAssertFalse(second.load())
        XCTAssertNil(defaults.object(forKey: "test.second"))
        XCTAssertNil(defaults.object(forKey: "logging.routeRecordingEnabled"))
    }
}
