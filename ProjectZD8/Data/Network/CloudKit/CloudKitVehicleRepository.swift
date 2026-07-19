import CloudKit
import CryptoKit
import Foundation

/// CloudKit private databaseと端末内キャッシュで車両カタログを保持します。
@MainActor
final class CloudKitVehicleRepository: VehicleRepository {
    /// 車両カタログを保存するCloudKitレコード種別です。
    private static let recordType = "VehicleCatalog"
    /// カタログAssetを保持するCloudKitフィールド名です。
    private static let catalogAssetKey = "catalogAsset"
    /// CloudKitが利用不能でも再起動時に一覧を復元する保存先です。
    private let defaults: UserDefaults
    /// テストまたは明示構成時に使用するCloudKitコンテナです。
    private let injectedContainer: CKContainer?
    /// Asset用一時ファイルを作成するファイルシステム境界です。
    private let fileManager: FileManager

    /// CloudKitコンテナ、ローカル保存先、ファイルシステムを注入します。
    ///
    /// 責務: 車両カタログの同期先とオフライン保存先を固定します。
    /// - Parameters:
    ///   - container: private databaseを提供するCloudKitコンテナ。
    ///   - defaults: オフライン用キャッシュ保存先。
    ///   - fileManager: Asset一時ファイルの操作境界。
    init(
        container: CKContainer? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        injectedContainer = container
        self.defaults = defaults
        self.fileManager = fileManager
    }

    /// CloudKitを優先し、利用不能時は端末内キャッシュから車両を読み込みます。
    ///
    /// 責務: 1件のアカウントカタログを同期先または保存済みキャッシュから復元します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: 更新日時の新しい順に並ぶ登録車両。
    func loadVehicles(for accountIdentifier: String) async throws -> [VehicleProfile] {
        do {
            let record = try await privateDatabase.record(for: recordID(for: accountIdentifier))
            guard
                let asset = record[Self.catalogAssetKey] as? CKAsset,
                let url = asset.fileURL,
                let data = try? Data(contentsOf: url),
                let vehicles = try? JSONDecoder().decode([VehicleProfile].self, from: data)
            else { return cachedVehicles(for: accountIdentifier) }
            let sorted = vehicles.sorted { $0.updatedAt > $1.updatedAt }
            cache(sorted, for: accountIdentifier)
            return sorted
        } catch let error as CKError where error.code == .unknownItem {
            return cachedVehicles(for: accountIdentifier)
        } catch {
            let cached = cachedVehicles(for: accountIdentifier)
            guard !cached.isEmpty else { throw error }
            return cached
        }
    }

    /// 車両1件を現在カタログへ統合してCloudKitとキャッシュへ保存します。
    ///
    /// 責務: 1件のプロフィール更新をアカウント別カタログへ反映します。
    /// - Parameters:
    ///   - vehicle: 保存する車両プロフィール。
    ///   - accountIdentifier: Appleアカウントのアプリ固有識別子。
    func saveVehicle(_ vehicle: VehicleProfile, for accountIdentifier: String) async throws {
        var vehicles = try await loadVehicles(for: accountIdentifier)
        if let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            vehicles[index] = vehicle
        } else {
            vehicles.append(vehicle)
        }
        try await persist(vehicles, for: accountIdentifier)
    }

    /// 車両1件を現在カタログから削除してCloudKitとキャッシュへ保存します。
    ///
    /// 責務: 指定IDのプロフィールだけをアカウント別カタログから除去します。
    /// - Parameters:
    ///   - id: 削除対象の車両ID。
    ///   - accountIdentifier: Appleアカウントのアプリ固有識別子。
    func deleteVehicle(id: VehicleID, for accountIdentifier: String) async throws {
        var vehicles = try await loadVehicles(for: accountIdentifier)
        vehicles.removeAll { $0.id == id }
        try await persist(vehicles, for: accountIdentifier)
    }

    /// 車両カタログ全体をAssetとしてCloudKitへ保存します。
    ///
    /// 責務: 1件のアカウントカタログを端末キャッシュとCloudKitレコードへ同じ内容で保存します。
    /// - Parameters:
    ///   - vehicles: 保存する全登録車両。
    ///   - accountIdentifier: Appleアカウントのアプリ固有識別子。
    private func persist(_ vehicles: [VehicleProfile], for accountIdentifier: String) async throws {
        let sorted = vehicles.sorted { $0.updatedAt > $1.updatedAt }
        let data = try JSONEncoder().encode(sorted)
        cache(sorted, for: accountIdentifier)
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("vehicle-catalog-\(UUID().uuidString).json")
        try data.write(to: temporaryURL, options: .atomic)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let id = recordID(for: accountIdentifier)
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: id)
        }
        record[Self.catalogAssetKey] = CKAsset(fileURL: temporaryURL)
        record["updatedAt"] = Date() as CKRecordValue
        _ = try await privateDatabase.save(record)
    }

    /// 利用時点で解決するCloudKit private databaseです。
    private var privateDatabase: CKDatabase {
        (injectedContainer ?? CKContainer.default()).privateCloudDatabase
    }

    /// Apple識別子を平文保存しないCloudKitレコードIDへ変換します。
    ///
    /// 責務: 1件のApple識別子を車両カタログ用の不可逆レコード名へ変換します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: private database内で安定するレコードID。
    private func recordID(for accountIdentifier: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "vehicle-catalog-\(fingerprint(for: accountIdentifier))")
    }

    /// Apple識別子を端末キャッシュ用の不可逆キーへ変換します。
    ///
    /// 責務: 1件のApple識別子からSHA-256フィンガープリントを生成します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: 小文字16進表現のSHA-256値。
    private func fingerprint(for accountIdentifier: String) -> String {
        SHA256.hash(data: Data(accountIdentifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// 指定アカウントの端末キャッシュを復号します。
    ///
    /// 責務: 1件のアカウントキーから復元可能な車両一覧を返します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: 復号できた車両一覧。未保存または破損時は空配列。
    private func cachedVehicles(for accountIdentifier: String) -> [VehicleProfile] {
        guard let data = defaults.data(forKey: cacheKey(for: accountIdentifier)) else { return [] }
        return (try? JSONDecoder().decode([VehicleProfile].self, from: data)) ?? []
    }

    /// 指定アカウントの端末キャッシュを更新します。
    ///
    /// 責務: 1件のアカウント車両一覧をオフライン復元用に符号化して保存します。
    /// - Parameters:
    ///   - vehicles: キャッシュする車両一覧。
    ///   - accountIdentifier: Appleアカウントのアプリ固有識別子。
    private func cache(_ vehicles: [VehicleProfile], for accountIdentifier: String) {
        guard let data = try? JSONEncoder().encode(vehicles) else { return }
        defaults.set(data, forKey: cacheKey(for: accountIdentifier))
    }

    /// 指定アカウントの端末キャッシュキーを生成します。
    ///
    /// 責務: 1件のApple識別子を世代付きキャッシュキーへ変換します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: 車両カタログ専用キャッシュキー。
    private func cacheKey(for accountIdentifier: String) -> String {
        "vehicle.catalog.v1.\(fingerprint(for: accountIdentifier))"
    }
}
