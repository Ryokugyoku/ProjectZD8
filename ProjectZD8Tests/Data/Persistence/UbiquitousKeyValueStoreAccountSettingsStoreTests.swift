import Foundation
import XCTest
@testable import ProjectZD8

/// iCloud KVSアカウント設定保存のローカル保持とスコープ分離を検証します。
@MainActor
final class UbiquitousKeyValueStoreAccountSettingsStoreTests: XCTestCase {
    /// 保存値が新しい保存アダプターでもローカル領域から復元できることを検証します。
    ///
    /// 責務: iCloud値がない再起動相当状態でも言語と外観がローカル保持されることを確認します。
    func testSavedSettingsSurviveLocalRelaunchWithoutCloudValue() throws {
        let suiteName = "UbiquitousKeyValueStoreAccountSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstCloud = UbiquitousKeyValueStorePortFake()
        let firstStore = UbiquitousKeyValueStoreAccountSettingsStore(
            defaults: defaults,
            ubiquitousStore: firstCloud,
            notificationCenter: NotificationCenter()
        )
        let expected = AccountSettings(language: .english, appearance: .dark)
        firstStore.save(expected, for: "account-a")

        let relaunchedStore = UbiquitousKeyValueStoreAccountSettingsStore(
            defaults: defaults,
            ubiquitousStore: UbiquitousKeyValueStorePortFake(),
            notificationCenter: NotificationCenter()
        )

        XCTAssertEqual(relaunchedStore.load(for: "account-a"), expected)
    }

    /// 同じ端末上でも異なるAppleユーザーの設定が分離されることを検証します。
    ///
    /// 責務: 2件のユーザー識別子を互いに異なる不可逆キーへ保存します。
    func testDifferentAccountsUseIsolatedKeysWithoutRawIdentifier() throws {
        let suiteName = "UbiquitousKeyValueStoreAccountSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cloud = UbiquitousKeyValueStorePortFake()
        let store = UbiquitousKeyValueStoreAccountSettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            notificationCenter: NotificationCenter()
        )
        let first = AccountSettings(language: .english, appearance: .dark)
        let second = AccountSettings(language: .spanish, appearance: .light)

        store.save(first, for: "private-apple-user-a")
        store.save(second, for: "private-apple-user-b")

        XCTAssertEqual(store.load(for: "private-apple-user-a"), first)
        XCTAssertEqual(store.load(for: "private-apple-user-b"), second)
        XCTAssertEqual(cloud.savedData.count, 2)
        XCTAssertFalse(cloud.savedData.keys.contains { $0.contains("private-apple-user") })
    }

    /// iCloud外部変更通知が監視対象アカウントだけへ反映されることを検証します。
    ///
    /// 責務: 変更キーが一致する1件の同期設定を購読コールバックとローカル保持へ渡します。
    func testExternalChangeUpdatesObservedAccount() throws {
        let suiteName = "UbiquitousKeyValueStoreAccountSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cloud = UbiquitousKeyValueStorePortFake()
        let notificationCenter = NotificationCenter()
        let store = UbiquitousKeyValueStoreAccountSettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            notificationCenter: notificationCenter
        )
        store.save(AccountSettings(), for: "account-a")
        let key = try XCTUnwrap(cloud.savedData.keys.first)
        var received: AccountSettings?
        store.startObserving(for: "account-a") { received = $0 }
        let external = AccountSettings(language: .spanish, appearance: .dark)
        cloud.savedData[key] = try JSONEncoder().encode(external)

        notificationCenter.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: [key]]
        )

        XCTAssertEqual(received, external)
        XCTAssertEqual(store.load(for: "account-a"), external)
        store.stopObserving()
    }

    /// アカウント削除がローカル設定とiCloud共有設定の両方を除去することを検証します。
    ///
    /// 責務: 1件のアカウント設定削除が両保存先に残存値を残さないことを確認します。
    func testRemoveDeletesLocalAndSynchronizedSettings() throws {
        let suiteName = "UbiquitousKeyValueStoreAccountSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cloud = UbiquitousKeyValueStorePortFake()
        let store = UbiquitousKeyValueStoreAccountSettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            notificationCenter: NotificationCenter()
        )
        store.save(AccountSettings(language: .english, appearance: .dark), for: "delete-account")

        store.remove(for: "delete-account")

        XCTAssertNil(store.load(for: "delete-account"))
        XCTAssertTrue(cloud.savedData.isEmpty)
    }
}

/// iCloud KVSテストでキー別データと同期要求を記録します。
private final class UbiquitousKeyValueStorePortFake: UbiquitousKeyValueStorePort {
    /// キーごとに保存されたテスト用同期データです。
    var savedData: [String: Data] = [:]

    /// 同期要求を受け取った回数です。
    private(set) var synchronizationCount = 0

    /// 指定キーのテスト用同期データを返します。
    ///
    /// 責務: 1件のキーに対応するFakeデータを読み込みます。
    /// - Parameter key: 読込対象の同期キー。
    /// - Returns: Fakeに保存されているデータ。
    func data(forKey key: String) -> Data? {
        savedData[key]
    }

    /// 指定キーへテスト用同期データを保存します。
    ///
    /// 責務: 1件の同期保存要求をキー別Fake領域へ記録します。
    /// - Parameters:
    ///   - data: 保存要求されたデータ。
    ///   - key: 保存対象の同期キー。
    func setData(_ data: Data, forKey key: String) {
        savedData[key] = data
    }

    /// 指定キーのテスト用同期データを削除します。
    ///
    /// 責務: 1件の削除要求をFakeのキー別データへ反映します。
    /// - Parameter key: 削除対象の同期キー。
    func removeObject(forKey key: String) {
        savedData.removeValue(forKey: key)
    }

    /// テスト用の同期要求を記録します。
    ///
    /// 責務: 1回の同期要求をテストから観測可能な回数へ加算します。
    /// - Returns: 常に `true`。
    @discardableResult
    func synchronize() -> Bool {
        synchronizationCount += 1
        return true
    }
}
