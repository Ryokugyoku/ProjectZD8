import CloudKit
import CryptoKit
import Foundation

/// CloudKit private databaseへ写真を含む整備カタログをAsset保存します。
@MainActor
final class CloudKitMaintenanceRemoteStore: MaintenanceRemoteStore {
    /// 整備カタログのCloudKitレコード種別です。
    private static let recordType = "MaintenanceCatalog"
    /// JSON Assetを保持するフィールド名です。
    private static let catalogAssetKey = "catalogAsset"
    /// テストまたは明示構成で使用するCloudKitコンテナです。
    private let injectedContainer: CKContainer?
    /// Asset一時ファイルを操作する境界です。
    private let fileManager: FileManager

    /// CloudKitコンテナとファイル境界を注入します。
    ///
    /// 責務: 整備カタログの遠隔保存先と一時Asset操作先を固定します。
    /// - Parameters:
    ///   - container: private databaseを提供するCloudKitコンテナ。
    ///   - fileManager: Asset一時ファイルの操作境界。
    init(container: CKContainer? = nil, fileManager: FileManager = .default) {
        injectedContainer = container
        self.fileManager = fileManager
    }

    /// CloudKitから写真と墓石を含む整備カタログを取得します。
    ///
    /// 責務: 1件のアカウント用Assetを整備記録集合へ復号します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: 遠隔保存されている整備記録集合。
    /// - Throws: CloudKit読込またはJSON復号に失敗した場合のエラー。
    func fetchRecords(for accountIdentifier: String) async throws -> [MaintenanceRecord] {
        do {
            let record = try await privateDatabase.record(for: recordID(for: accountIdentifier))
            guard let asset = record[Self.catalogAssetKey] as? CKAsset,
                  let url = asset.fileURL else { return [] }
            return try JSONDecoder().decode([MaintenanceRecord].self, from: Data(contentsOf: url))
        } catch let error as CKError where error.code == .unknownItem {
            return []
        }
    }

    /// 写真と墓石を含む整備カタログをCloudKit Assetへ保存します。
    ///
    /// 責務: 1件のアカウント用整備集合を原子的なJSON Assetとして更新します。
    /// - Parameters:
    ///   - records: 保存する整備記録集合。
    ///   - accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Throws: JSON符号化、一時ファイル、CloudKit保存に失敗した場合のエラー。
    func saveRecords(_ records: [MaintenanceRecord], for accountIdentifier: String) async throws {
        let data = try JSONEncoder().encode(records)
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("maintenance-catalog-\(UUID().uuidString).json")
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

    /// Apple識別子を平文保存しない整備カタログIDへ変換します。
    ///
    /// 責務: 1件のApple識別子を整備カタログ用の不可逆レコード名へ変換します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: private database内で安定するレコードID。
    private func recordID(for accountIdentifier: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "maintenance-catalog-\(fingerprint(for: accountIdentifier))")
    }

    /// Apple識別子からSHA-256フィンガープリントを生成します。
    ///
    /// 責務: 1件のApple識別子を小文字16進の不可逆値へ変換します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: 小文字16進表現のSHA-256値。
    private func fingerprint(for accountIdentifier: String) -> String {
        SHA256.hash(data: Data(accountIdentifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
