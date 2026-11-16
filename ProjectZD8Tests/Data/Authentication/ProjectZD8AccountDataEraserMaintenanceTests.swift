import Foundation
import XCTest
@testable import ProjectZD8

/// アカウント削除の端末内消去が整備記録を対象に含めることを検証します。
///
/// 仮定API: `ProjectZD8AccountDataEraser.init` の `maintenanceRecordRepository: any MaintenanceRecordRepository` 引数
/// (`vehiclePIDCapabilityEraser:` の次)。未実装のためコンパイルエラーで失敗します。
/// 整備記録の消去は既存の `replaceAll(_:for:)`(空集合)または新設の削除APIのどちらでも `records(for:)` が空になれば合格です。
@MainActor
final class ProjectZD8AccountDataEraserMaintenanceTests: XCTestCase {
    /// 削除対象アカウントの整備記録だけが端末から消えることを検証します。
    ///
    /// 責務: `eraseAllData` が対象アカウントの整備記録を消し、他アカウントの記録は残すことを確認します。
    func testEraseAllDataRemovesMaintenanceRecordsOfTheAccountOnly() async throws {
        let suiteName = "ProjectZD8AccountDataEraserMaintenanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let maintenance = MaintenanceRecordRepositoryFake()
        try await maintenance.save(makeRecord(title: "mine"), for: "account")
        try await maintenance.save(makeRecord(title: "other"), for: "other-account")
        let eraser = ProjectZD8AccountDataEraser(
            accountSettingsStore: UbiquitousKeyValueStoreAccountSettingsStore(
                defaults: defaults,
                ubiquitousStore: MaintenanceEraserUbiquitousStoreFake(),
                notificationCenter: NotificationCenter()
            ),
            defaultAdapterStore: UserDefaultsDefaultAdapterPreferenceStore(defaults: defaults),
            connectionSessionStorage: MaintenanceEraserSessionRepositoryFake(),
            vehicleDataEraser: MaintenanceEraserVehiclePortFake(),
            vehiclePIDCapabilityEraser: MaintenanceEraserCapabilityRepositoryFake(),
            maintenanceRecordRepository: maintenance
        )

        try await eraser.eraseAllData(for: "account")

        let mine = try await maintenance.records(for: "account")
        let other = try await maintenance.records(for: "other-account")
        XCTAssertTrue(mine.isEmpty, "削除したアカウントの整備記録が端末に残っています。")
        XCTAssertEqual(other.map(\.title), ["other"])
    }

    /// 検証用の整備記録を生成します。
    ///
    /// 責務: 1件の最小の整備記録を作ります。
    /// - Parameter title: 記録の題名。
    /// - Returns: 整備記録。
    private func makeRecord(title: String) -> MaintenanceRecord {
        MaintenanceRecord(
            id: MaintenanceRecordID(),
            vehicleID: VehicleID(),
            kind: .light,
            title: title,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

/// アカウント別の整備記録をメモリ上で保持するリポジトリFakeです。
private actor MaintenanceRecordRepositoryFake: MaintenanceRecordRepository {
    /// アカウント識別子ごとの整備記録です。
    private var storage: [String: [MaintenanceRecord]] = [:]

    /// 指定アカウントの整備記録を返します。
    ///
    /// 責務: メモリ上の1アカウント分を返します。
    /// - Parameter accountIdentifier: アカウント識別子。
    /// - Returns: 保持している整備記録。
    func records(for accountIdentifier: String) async throws -> [MaintenanceRecord] {
        storage[accountIdentifier] ?? []
    }

    /// 整備記録を追加または置換します。
    ///
    /// 責務: 同じIDの記録を置き換えて1件保存します。
    /// - Parameters:
    ///   - record: 保存する記録。
    ///   - accountIdentifier: アカウント識別子。
    func save(_ record: MaintenanceRecord, for accountIdentifier: String) async throws {
        storage[accountIdentifier, default: []].removeAll { $0.id == record.id }
        storage[accountIdentifier, default: []].append(record)
    }

    /// アカウントの整備記録を渡された集合で置き換えます。
    ///
    /// 責務: 1アカウント分をまとめて置換します。
    /// - Parameters:
    ///   - records: 新しい集合。
    ///   - accountIdentifier: アカウント識別子。
    func replaceAll(_ records: [MaintenanceRecord], for accountIdentifier: String) async throws {
        storage[accountIdentifier] = records
    }
}

/// 端末内接続履歴の削除要求を受け流すFakeです。
private final class MaintenanceEraserSessionRepositoryFake: AccountConnectionSessionErasureRepository {
    /// 削除要求を受け流します。
    ///
    /// 責務: このテストで対象外の削除境界を満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func deleteSessions(for accountIdentifier: String) throws {}
}

/// 車両の端末キャッシュ削除要求を受け流すFakeです。
@MainActor
private final class MaintenanceEraserVehiclePortFake: AccountVehicleDataErasurePort {
    /// 使用しないCloudKit削除を受け流します。
    ///
    /// 責務: このテストで対象外の境界を満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func deleteAllVehicleData(for accountIdentifier: String) async throws {}

    /// 空の車両ID群を返します。
    ///
    /// 責務: このテストで対象外の照会を満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func localVehicleIDs(for accountIdentifier: String) -> [VehicleID] { [] }

    /// キャッシュ削除を受け流します。
    ///
    /// 責務: このテストで対象外の境界を満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func removeLocalVehicleCache(for accountIdentifier: String) {}
}

/// 車両別PID設定の削除要求を受け流すFakeです。
private final class MaintenanceEraserCapabilityRepositoryFake: AccountVehiclePIDCapabilityErasureRepository {
    /// 削除要求を受け流します。
    ///
    /// 責務: このテストで対象外の削除境界を満たします。
    /// - Parameter vehicleIDs: 使用しない車両ID群。
    func deleteCapabilities(for vehicleIDs: [VehicleID]) throws {}
}

/// iCloud KVSを空のメモリ上保存先として再現するFakeです。
private final class MaintenanceEraserUbiquitousStoreFake: UbiquitousKeyValueStorePort {
    /// キー別データです。
    private var values: [String: Data] = [:]

    /// 指定キーのデータを返します。
    ///
    /// 責務: メモリ上の1キーを返します。
    /// - Parameter key: キー。
    /// - Returns: 保存済みデータ。
    func data(forKey key: String) -> Data? { values[key] }

    /// 指定キーへデータを保存します。
    ///
    /// 責務: メモリ上へ1件保存します。
    /// - Parameters:
    ///   - data: データ。
    ///   - key: キー。
    func setData(_ data: Data, forKey key: String) { values[key] = data }

    /// 指定キーを削除します。
    ///
    /// 責務: メモリ上の1キーを除去します。
    /// - Parameter key: キー。
    func removeObject(forKey key: String) { values[key] = nil }

    /// 同期要求を成功として受理します。
    ///
    /// 責務: 固定成功を返します。
    /// - Returns: 常に `true`。
    func synchronize() -> Bool { true }
}
