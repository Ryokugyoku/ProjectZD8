import Foundation
import XCTest
@testable import ProjectZD8

/// iCloud KVSセッション失効ストアの世代比較と通知分離を検証します。
@MainActor
final class UbiquitousKeyValueStoreAccountSessionRevocationStoreTests: XCTestCase {
    /// 新規ログインが現在の失効世代を受理して即時ログアウトしないことを検証します。
    ///
    /// 責務: 登録済み世代と同じiCloud値が失効通知へ変換されないことを確認します。
    func testRegisteredCurrentSessionDoesNotReceiveExistingRevocation() throws {
        let dependencies = try makeDependencies()
        defer { dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName) }
        dependencies.store.publishRevocation(for: "account-a")
        dependencies.store.registerCurrentSession(for: "account-a")
        var deliveryCount = 0

        dependencies.store.startObserving(for: "account-a") { deliveryCount += 1 }

        XCTAssertEqual(deliveryCount, 0)
        dependencies.store.stopObserving()
    }

    /// 監視開始後に届いた新しい失効世代を同一世代につき1回だけ通知することを検証します。
    ///
    /// 責務: 1件の外部失効世代を重複しないコールバックへ変換することを確認します。
    func testExternalRevocationIsDeliveredOnlyOncePerMarker() throws {
        let dependencies = try makeDependencies()
        defer { dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName) }
        dependencies.store.registerCurrentSession(for: "account-a")
        var deliveryCount = 0
        dependencies.store.startObserving(for: "account-a") { deliveryCount += 1 }
        dependencies.store.publishRevocation(for: "account-a")
        let key = try XCTUnwrap(dependencies.cloud.savedData.keys.first)

        dependencies.notificationCenter.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: dependencies.cloud,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: [key]]
        )
        dependencies.notificationCenter.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: dependencies.cloud,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: [key]]
        )

        XCTAssertEqual(deliveryCount, 1)
        dependencies.store.stopObserving()
    }

    /// オフライン中に更新された失効世代を次回監視開始時に検出することを検証します。
    ///
    /// 責務: 通知を直接受けなかった端末でも保存済み基準との差から失効を検出することを確認します。
    func testObservationStartDetectsRevocationMissedWhileOffline() throws {
        let dependencies = try makeDependencies()
        defer { dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName) }
        dependencies.store.registerCurrentSession(for: "account-a")
        dependencies.store.publishRevocation(for: "account-a")
        let relaunchedStore = UbiquitousKeyValueStoreAccountSessionRevocationStore(
            defaults: dependencies.defaults,
            ubiquitousStore: dependencies.cloud,
            notificationCenter: dependencies.notificationCenter
        )
        var deliveryCount = 0

        relaunchedStore.startObserving(for: "account-a") { deliveryCount += 1 }

        XCTAssertEqual(deliveryCount, 1)
        relaunchedStore.stopObserving()
    }

    /// 失効同期キーがAppleユーザー識別子を直接含まずアカウントごとに分離されることを検証します。
    ///
    /// 責務: 2件のユーザー識別子を互いに異なる不可逆失効キーへ変換することを確認します。
    func testRevocationKeysAreAccountScopedWithoutRawIdentifier() throws {
        let dependencies = try makeDependencies()
        defer { dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName) }

        dependencies.store.publishRevocation(for: "private-user-a")
        dependencies.store.publishRevocation(for: "private-user-b")

        XCTAssertEqual(dependencies.cloud.savedData.count, 2)
        XCTAssertFalse(dependencies.cloud.savedData.keys.contains { $0.contains("private-user") })
    }

    /// 失効ストアテストで共有する隔離済み保存境界を生成します。
    ///
    /// 責務: 1件のテストへ専用UserDefaults、Fake iCloud、通知中心、検証対象を同一構成で提供します。
    /// - Returns: テスト専用の失効ストア依存関係。
    /// - Throws: テスト専用UserDefaultsを生成できない場合のアンラップ失敗。
    private func makeDependencies() throws -> RevocationStoreTestDependencies {
        let suiteName = "UbiquitousKeyValueStoreAccountSessionRevocationStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let cloud = RevocationUbiquitousKeyValueStorePortFake()
        let notificationCenter = NotificationCenter()
        return RevocationStoreTestDependencies(
            suiteName: suiteName,
            defaults: defaults,
            cloud: cloud,
            notificationCenter: notificationCenter,
            store: UbiquitousKeyValueStoreAccountSessionRevocationStore(
                defaults: defaults,
                ubiquitousStore: cloud,
                notificationCenter: notificationCenter
            )
        )
    }
}

/// 失効ストアテストで共有する保存境界の組です。
@MainActor
private struct RevocationStoreTestDependencies {
    /// テスト専用UserDefaultsドメイン名です。
    let suiteName: String

    /// 受理済み世代を保持するテスト専用ローカル保存先です。
    let defaults: UserDefaults

    /// 最新失効世代を保持するFake iCloud保存先です。
    let cloud: RevocationUbiquitousKeyValueStorePortFake

    /// 外部変更をテストから発行する通知中心です。
    let notificationCenter: NotificationCenter

    /// 検証対象のセッション失効ストアです。
    let store: UbiquitousKeyValueStoreAccountSessionRevocationStore
}

/// セッション失効テストでキー別データと同期要求を記録します。
private final class RevocationUbiquitousKeyValueStorePortFake: UbiquitousKeyValueStorePort {
    /// キーごとに保存されたテスト用失効世代です。
    var savedData: [String: Data] = [:]

    /// 同期要求を受け取った回数です。
    private(set) var synchronizationCount = 0

    /// 指定キーのテスト用失効世代を返します。
    ///
    /// 責務: 1件のキーに対応するFakeデータを読み込みます。
    /// - Parameter key: 読込対象の同期キー。
    /// - Returns: Fakeに保存されているデータ。
    func data(forKey key: String) -> Data? {
        savedData[key]
    }

    /// 指定キーへテスト用失効世代を保存します。
    ///
    /// 責務: 1件の失効世代保存要求をキー別Fake領域へ記録します。
    /// - Parameters:
    ///   - data: 保存要求された失効世代。
    ///   - key: 保存対象の同期キー。
    func setData(_ data: Data, forKey key: String) {
        savedData[key] = data
    }

    /// 指定キーのテスト用失効世代を削除します。
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
