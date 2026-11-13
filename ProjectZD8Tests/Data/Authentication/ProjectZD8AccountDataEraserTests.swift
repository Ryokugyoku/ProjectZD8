import Foundation
import XCTest
@testable import ProjectZD8

/// 遠隔失効でも使用する端末内アカウントデータ消去を検証します。
@MainActor
final class ProjectZD8AccountDataEraserTests: XCTestCase {
    /// 運転履歴、車両キャッシュ、設定、アダプター選択を同じアカウント削除で消去します。
    ///
    /// 責務: 別端末の失効検知後に現在端末へアカウント固有ローカルデータが残らないことを確認します。
    func testEraseAllDataRemovesEveryAccountScopedLocalStore() throws {
        let suiteName = "ProjectZD8AccountDataEraserTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cloud = AccountDataErasureUbiquitousStoreFake()
        let settings = UbiquitousKeyValueStoreAccountSettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            notificationCenter: NotificationCenter()
        )
        let adapter = UserDefaultsDefaultAdapterPreferenceStore(defaults: defaults)
        let sessions = AccountConnectionSessionErasureRepositoryFake()
        let vehicles = AccountVehicleDataErasurePortFake()
        let capabilities = AccountVehiclePIDCapabilityErasureRepositoryFake()
        settings.save(AccountSettings(language: .english, appearance: .dark), for: "account")
        adapter.save(
            DefaultAdapterPreference(
                adapterID: "usb:adapter",
                transportMode: .usb,
                displayName: "ZD8 Adapter",
                systemIdentifier: "/dev/cu.test"
            )
        )
        let eraser = ProjectZD8AccountDataEraser(
            accountSettingsStore: settings,
            defaultAdapterStore: adapter,
            connectionSessionStorage: sessions,
            vehicleDataEraser: vehicles,
            vehiclePIDCapabilityEraser: capabilities
        )

        try eraser.eraseAllData(for: "account")

        XCTAssertEqual(sessions.deletedAccountIdentifiers, ["account"])
        XCTAssertEqual(vehicles.removedLocalCacheIdentifiers, ["account"])
        XCTAssertEqual(capabilities.deletedVehicleIDs, vehicles.localIDs)
        XCTAssertNil(settings.load(for: "account"))
        XCTAssertNil(adapter.load())
        XCTAssertTrue(cloud.values.isEmpty)
    }
}

/// 端末内接続履歴のアカウント削除要求を記録します。
private final class AccountConnectionSessionErasureRepositoryFake: AccountConnectionSessionErasureRepository {
    /// 削除されたアカウント識別子です。
    private(set) var deletedAccountIdentifiers: [String] = []

    /// 削除対象アカウントを記録します。
    ///
    /// 責務: 1件のローカル運転データ削除要求を検査可能な履歴へ追加します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteSessions(for accountIdentifier: String) throws {
        deletedAccountIdentifiers.append(accountIdentifier)
    }
}

/// 車両カタログの端末キャッシュ削除要求を記録します。
@MainActor
private final class AccountVehicleDataErasurePortFake: AccountVehicleDataErasurePort {
    /// 端末キャッシュを削除されたアカウント識別子です。
    private(set) var removedLocalCacheIdentifiers: [String] = []
    /// 端末キャッシュに存在する固定車両IDです。
    let localIDs = [VehicleID(), VehicleID()]

    /// このテストではCloudKit車両削除を使用しません。
    ///
    /// 責務: テスト対象外の全保存先削除要求を副作用なしで満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func deleteAllVehicleData(for accountIdentifier: String) async throws {}

    /// 固定の端末内登録車両IDを返します。
    ///
    /// 責務: 車両別PID設定削除へテスト用車両ID群を供給します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 初期化済みの固定車両ID群。
    func localVehicleIDs(for accountIdentifier: String) -> [VehicleID] { localIDs }

    /// 端末キャッシュ削除対象を記録します。
    ///
    /// 責務: 1件の車両キャッシュ削除要求を検査可能な履歴へ追加します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func removeLocalVehicleCache(for accountIdentifier: String) {
        removedLocalCacheIdentifiers.append(accountIdentifier)
    }
}

/// 車両別PID設定の削除要求を記録します。
private final class AccountVehiclePIDCapabilityErasureRepositoryFake: AccountVehiclePIDCapabilityErasureRepository {
    /// 削除された車両ID群です。
    private(set) var deletedVehicleIDs: [VehicleID] = []

    /// 削除対象車両ID群を記録します。
    ///
    /// 責務: 1回の車両別PID設定削除を検査可能なID配列へ保存します。
    /// - Parameter vehicleIDs: 削除対象車両ID群。
    func deleteCapabilities(for vehicleIDs: [VehicleID]) throws {
        deletedVehicleIDs = vehicleIDs
    }
}

/// アカウント設定のiCloud KVS操作をメモリ上で再現します。
private final class AccountDataErasureUbiquitousStoreFake: UbiquitousKeyValueStorePort {
    /// キー別の同期データです。
    var values: [String: Data] = [:]

    /// 指定キーの同期データを返します。
    ///
    /// 責務: 1件のキーを現在のメモリ上データへ解決します。
    /// - Parameter key: 読み込むキー。
    /// - Returns: 保存済みの場合のデータ。
    func data(forKey key: String) -> Data? { values[key] }

    /// 指定キーへ同期データを保存します。
    ///
    /// 責務: 1件の同期データをメモリ上のキーへ関連付けます。
    /// - Parameters:
    ///   - data: 保存するデータ。
    ///   - key: 保存先キー。
    func setData(_ data: Data, forKey key: String) { values[key] = data }

    /// 指定キーの同期データを削除します。
    ///
    /// 責務: 1件のキーをメモリ上の同期データから除去します。
    /// - Parameter key: 削除対象キー。
    func removeObject(forKey key: String) { values[key] = nil }

    /// 同期要求を成功として受理します。
    ///
    /// 責務: テスト用KVSの同期要求へ固定成功を返します。
    /// - Returns: 常に `true`。
    func synchronize() -> Bool { true }
}
