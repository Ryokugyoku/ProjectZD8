import Foundation
import XCTest
@testable import ProjectZD8

/// 遠隔失効でも使用する端末内アカウントデータ消去を検証します。
@MainActor
final class ProjectZD8AccountDataEraserTests: XCTestCase {
    /// 運転履歴、車両キャッシュ、設定、アダプター選択を同じアカウント削除で消去します。
    ///
    /// 責務: 別端末の失効検知後に現在端末へアカウント固有ローカルデータが残らないことを確認します。
    func testEraseAllDataRemovesEveryAccountScopedLocalStore() async throws {
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
        let maintenance = AccountMaintenanceRecordRepositoryFake()
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
            vehiclePIDCapabilityEraser: capabilities,
            maintenanceRecordRepository: maintenance
        )

        try await eraser.eraseAllData(for: "account")

        XCTAssertEqual(sessions.deletedAccountIdentifiers, ["account"])
        XCTAssertEqual(vehicles.removedLocalCacheIdentifiers, ["account"])
        XCTAssertEqual(capabilities.deletedVehicleIDs, vehicles.localIDs)
        let replaced = await maintenance.replacedAccounts
        XCTAssertEqual(replaced, ["account"])
        XCTAssertNil(settings.load(for: "account"))
        XCTAssertNil(adapter.load())
        XCTAssertTrue(cloud.values.isEmpty)
    }

    /// 車両キャッシュが既に消えていても、控えた車両IDの別PID設定を消去することを検証します。
    ///
    /// 責務: 車両のクラウド削除直後にキャッシュを消す削除順序でも、PID設定が取り残されないことを確認します。
    func testEraseAllDataUsesKnownVehicleIDsWhenCacheIsAlreadyEmpty() async throws {
        let suiteName = "ProjectZD8AccountDataEraserTests.known.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let capabilities = AccountVehiclePIDCapabilityErasureRepositoryFake()
        let eraser = ProjectZD8AccountDataEraser(
            accountSettingsStore: UbiquitousKeyValueStoreAccountSettingsStore(
                defaults: defaults,
                ubiquitousStore: AccountDataErasureUbiquitousStoreFake(),
                notificationCenter: NotificationCenter()
            ),
            defaultAdapterStore: UserDefaultsDefaultAdapterPreferenceStore(defaults: defaults),
            connectionSessionStorage: AccountConnectionSessionErasureRepositoryFake(),
            vehicleDataEraser: AccountVehicleDataErasurePortFake(),
            vehiclePIDCapabilityEraser: capabilities,
            maintenanceRecordRepository: AccountMaintenanceRecordRepositoryFake()
        )
        let known = [VehicleID(), VehicleID()]

        try await eraser.eraseAllData(for: "account", knownVehicleIDs: known)

        XCTAssertEqual(capabilities.deletedVehicleIDs, known)
    }
}

/// 整備記録の全置換(空集合)要求を記録します。
private actor AccountMaintenanceRecordRepositoryFake: MaintenanceRecordRepository {
    /// 全置換を要求されたアカウント識別子です。
    private(set) var replacedAccounts: [String] = []

    /// 使用しない読込へ空配列を返します。
    ///
    /// 責務: このテストで対象外の読込境界を満たします。
    /// - Parameter _: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func records(for _: String) async throws -> [MaintenanceRecord] { [] }

    /// 使用しない保存を受け流します。
    ///
    /// 責務: このテストで対象外の保存境界を満たします。
    /// - Parameters:
    ///   - _: 使用しない記録。
    ///   - _: 使用しないアカウント識別子。
    func save(_: MaintenanceRecord, for _: String) async throws {
        // このテストでは呼び出しを観測しないため、何もしない。
    }

    /// 空集合での全置換だけを受け付けて記録します。
    ///
    /// 責務: 1件の整備記録全削除要求を検査可能な履歴へ追加します。
    /// - Parameters:
    ///   - records: 置き換える集合。空であることを要求します。
    ///   - accountIdentifier: 削除対象アカウント識別子。
    func replaceAll(_ records: [MaintenanceRecord], for accountIdentifier: String) async throws {
        guard records.isEmpty else { return }
        replacedAccounts.append(accountIdentifier)
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
