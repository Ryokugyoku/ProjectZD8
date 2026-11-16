import CloudKit
import CryptoKit
import Foundation

/// CloudKit private databaseへ、削除時刻だけを持つ削除済みの印を保存します。
@MainActor
final class CloudKitAccountDeletionMarkerStore: AccountDeletionMarkerPort {
    /// 削除済みの印のCloudKitレコード種別です。
    private static let recordType = "AccountDeletionMarker"
    /// 削除時刻を保持するフィールド名です。
    private static let deletedAtKey = "deletedAt"
    /// テストまたは明示構成で使用するCloudKitコンテナです。
    private let injectedContainer: CKContainer?
    /// 削除時刻の取得に使う時計です。
    private let now: () -> Date

    /// CloudKitコンテナと時計を注入します。
    ///
    /// 責務: 印の保存先と削除時刻の取得元を固定します。
    /// - Parameters:
    ///   - container: private databaseを提供するCloudKitコンテナ。省略時は既定コンテナ。
    ///   - now: 削除時刻を返す処理。
    init(container: CKContainer? = nil, now: @escaping () -> Date = Date.init) {
        injectedContainer = container
        self.now = now
    }

    /// 削除済みの印が存在するかを返します。
    ///
    /// 責務: 1件のアカウントの印レコードを取得し、存在しなければ「印なし」とします。
    /// - Parameter accountIdentifier: 照会対象のAppleアカウント識別子。
    /// - Returns: 印が存在する場合は `true`。
    /// - Throws: `unknownItem` 以外のCloudKitエラー。
    func isAccountDeleted(_ accountIdentifier: String) async throws -> Bool {
        do {
            _ = try await privateDatabase.record(for: recordID(for: accountIdentifier))
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        }
    }

    /// 削除済みの印を保存します。
    ///
    /// 責務: 削除時刻だけを持つ印レコードを1件保存します。既にあれば削除時刻を更新します。
    /// - Parameter accountIdentifier: 削除したAppleアカウント識別子。
    /// - Throws: CloudKit保存に失敗した場合のエラー。
    func markDeleted(_ accountIdentifier: String) async throws {
        let id = recordID(for: accountIdentifier)
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: id)
        }
        record[Self.deletedAtKey] = now() as CKRecordValue
        _ = try await privateDatabase.save(record)
    }

    /// 削除済みの印を消します。
    ///
    /// 責務: 印レコードを削除します。既に無ければ成功として扱います。
    /// - Parameter accountIdentifier: 利用を再開するAppleアカウント識別子。
    /// - Throws: `unknownItem` 以外のCloudKitエラー。
    func clearMarker(_ accountIdentifier: String) async throws {
        do {
            _ = try await privateDatabase.deleteRecord(withID: recordID(for: accountIdentifier))
        } catch let error as CKError where error.code == .unknownItem {
            // 既に印が無ければ目的状態を満たします。
        }
    }

    /// 利用時点で解決するCloudKit private databaseです。
    private var privateDatabase: CKDatabase {
        (injectedContainer ?? CKContainer.default()).privateCloudDatabase
    }

    /// Apple識別子を平文保存しない印のレコードIDへ変換します。
    ///
    /// 責務: 1件のApple識別子を `account-deletion-<SHA-256>` 形式の不可逆なレコード名へ変換します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: private database内で安定するレコードID。
    private func recordID(for accountIdentifier: String) -> CKRecord.ID {
        let fingerprint = SHA256.hash(data: Data(accountIdentifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return CKRecord.ID(recordName: "account-deletion-\(fingerprint)")
    }
}
