import CloudKit
import CryptoKit
import Foundation

/// CloudKit private databaseで接続セッションAssetとMac取込受領証を交換します。
@MainActor
final class CloudKitConnectionSessionTransferRepository: ConnectionSessionTransferRepository {
    /// セッションPayloadを保持するCloudKitレコード種別です。
    private static let transferRecordType = "ConnectionSessionRawLog"
    /// Mac取込受領証を保持するCloudKitレコード種別です。
    private static let receiptRecordType = "ConnectionSessionMacReceipt"
    /// 全端末へセッション物理削除を伝えるCloudKitレコード種別です。
    private static let deletionRecordType = "ConnectionSessionDeletion"
    /// セッションPayload Assetのフィールド名です。
    private static let payloadAssetKey = "payloadAsset"
    /// 同期アカウントの不可逆識別値フィールドです。
    private static let accountFingerprintKey = "accountFingerprint"
    /// セッションUUIDフィールドです。
    private static let sessionIDKey = "sessionID"
    /// AssetバイトSHA-256フィールドです。
    private static let manifestDigestKey = "manifestDigest"

    /// テストまたは明示構成時に使用するCloudKitコンテナです。
    private let injectedContainer: CKContainer?
    /// Asset用一時ファイルを操作するファイルシステム境界です。
    private let fileManager: FileManager
    /// セッションPayloadの安定したJSON Codecです。
    private let encoder: JSONEncoder
    /// セッションPayloadを復元するJSON Codecです。
    private let decoder: JSONDecoder

    /// CloudKitコンテナと一時ファイル境界を固定して生成します。
    ///
    /// 責務: セッション転送先と決定的Payload Codecを1件のCloudKit実装へ結び付けます。
    /// - Parameters:
    ///   - container: private databaseを提供するCloudKitコンテナ。
    ///   - fileManager: Asset一時ファイルを操作する境界。
    init(container: CKContainer? = nil, fileManager: FileManager = .default) {
        injectedContainer = container
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    /// 終了済みセッションPayloadをCloudKit Assetへ保存します。
    ///
    /// 責務: 1件のセッションPayloadをSHA-256付きCloudKitレコードへ変換します。
    /// - Parameters:
    ///   - package: 保存するセッションと未デコードRawログ。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: 保存したAssetバイトのSHA-256。
    /// - Throws: 状態検証、符号化、一時ファイル、またはCloudKit保存に失敗した場合のエラー。
    func upload(
        _ package: ConnectionSessionTransferPackage,
        for accountIdentifier: String
    ) async throws -> String {
        guard package.session.endedAt != nil,
              package.session.accountIdentifier == accountIdentifier else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        let data = try encoder.encode(package)
        let digest = sha256(data)
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("session-\(package.session.id.rawValue.uuidString)-\(UUID().uuidString).json")
        try data.write(to: temporaryURL, options: .atomic)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let id = transferRecordID(sessionID: package.session.id, accountIdentifier: accountIdentifier)
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.transferRecordType, recordID: id)
        }
        record[Self.accountFingerprintKey] = fingerprint(for: accountIdentifier) as CKRecordValue
        record[Self.sessionIDKey] = package.session.id.rawValue.uuidString.lowercased() as CKRecordValue
        record[Self.manifestDigestKey] = digest as CKRecordValue
        record["vehicleID"] = package.session.vehicle?.id.rawValue.uuidString.lowercased() as CKRecordValue?
        record["endedAt"] = package.session.endedAt as CKRecordValue?
        record[Self.payloadAssetKey] = CKAsset(fileURL: temporaryURL)
        _ = try await privateDatabase.save(record)
        return digest
    }

    /// 指定アカウントの全セッションAssetを検証して復元します。
    ///
    /// 責務: CloudKit上のセッションレコード群をDigest検証済み転送Payloadへ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: Asset SHA-256が保存済みManifestと一致したセッションPayload。
    /// - Throws: CloudKit取得、Asset読込、Digest検証、または復号に失敗した場合のエラー。
    func downloadTransfers(for accountIdentifier: String) async throws -> [VerifiedConnectionSessionTransfer] {
        let records = try await records(
            recordType: Self.transferRecordType,
            accountIdentifier: accountIdentifier
        )
        return try records.map { record in
            guard let asset = record[Self.payloadAssetKey] as? CKAsset,
                  let url = asset.fileURL,
                  let expectedDigest = record[Self.manifestDigestKey] as? String else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            let data = try Data(contentsOf: url)
            guard sha256(data) == expectedDigest else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            let package = try decoder.decode(ConnectionSessionTransferPackage.self, from: data)
            guard package.session.accountIdentifier == accountIdentifier,
                  package.session.id.rawValue.uuidString.caseInsensitiveCompare(
                    record[Self.sessionIDKey] as? String ?? ""
                  ) == .orderedSame else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            return VerifiedConnectionSessionTransfer(
                package: package,
                manifestDigest: expectedDigest
            )
        }
    }

    /// Macの永続取込受領証をCloudKitへ保存します。
    ///
    /// 責務: 1件のMac取込結果をセッションとMacインストール別の受領証レコードへ変換します。
    /// - Parameters:
    ///   - receipt: Macが読み戻し検証したManifest受領証。
    ///   - sessionID: 取り込んだ接続セッションID。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Throws: CloudKit保存を完了できない場合のエラー。
    func publishMacReceipt(
        _ receipt: ConnectionSessionMacImportReceipt,
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws {
        let id = receiptRecordID(
            sessionID: sessionID,
            deviceID: receipt.deviceID,
            accountIdentifier: accountIdentifier
        )
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.receiptRecordType, recordID: id)
        }
        record[Self.accountFingerprintKey] = fingerprint(for: accountIdentifier) as CKRecordValue
        record[Self.sessionIDKey] = sessionID.rawValue.uuidString.lowercased() as CKRecordValue
        record[Self.manifestDigestKey] = receipt.manifestDigest as CKRecordValue
        record["deviceID"] = receipt.deviceID as CKRecordValue
        record["deviceName"] = receipt.deviceName as CKRecordValue
        record["importedAt"] = receipt.importedAt as CKRecordValue
        _ = try await privateDatabase.save(record)
    }

    /// 指定アカウントのMac取込受領証を復元します。
    ///
    /// 責務: CloudKit受領証レコード群をセッションIDとMac取込結果の組へ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: 取込日時が新しい順のセッションIDと受領証。
    /// - Throws: CloudKit取得または必須フィールド復元に失敗した場合のエラー。
    func downloadMacReceipts(
        for accountIdentifier: String
    ) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] {
        let records = try await records(
            recordType: Self.receiptRecordType,
            accountIdentifier: accountIdentifier
        )
        return try records.map { record in
            guard let sessionIDString = record[Self.sessionIDKey] as? String,
                  let sessionUUID = UUID(uuidString: sessionIDString),
                  let deviceID = record["deviceID"] as? String,
                  let deviceName = record["deviceName"] as? String,
                  let importedAt = record["importedAt"] as? Date,
                  let digest = record[Self.manifestDigestKey] as? String else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            return (
                ConnectionSessionID(rawValue: sessionUUID),
                ConnectionSessionMacImportReceipt(
                    deviceID: deviceID,
                    deviceName: deviceName,
                    importedAt: importedAt,
                    manifestDigest: digest
                )
            )
        }
        .sorted { $0.1.importedAt > $1.1.importedAt }
    }

    /// 指定アカウントのセッション削除マーカーを復元します。
    ///
    /// 責務: CloudKit削除マーカー群を重複のない接続セッションID集合へ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: 全端末から物理削除すべき接続セッションID集合。
    /// - Throws: CloudKit取得または不正なセッションID復元に失敗した場合のエラー。
    func deletedSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID> {
        let deletionRecords = try await records(
            recordType: Self.deletionRecordType,
            accountIdentifier: accountIdentifier
        )
        return try Set(deletionRecords.map { record in
            guard let sessionIDString = record[Self.sessionIDKey] as? String,
                  let sessionUUID = UUID(uuidString: sessionIDString) else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            return ConnectionSessionID(rawValue: sessionUUID)
        })
    }

    /// 削除マーカーを保存して対応するCloudKit転送Payloadと受領証を物理削除します。
    ///
    /// 責務: 1件の接続セッションを全端末削除対象として永続化し運転データレコードを物理削除します。
    /// - Parameters:
    ///   - sessionID: 削除対象の接続セッションID。
    ///   - accountIdentifier: 削除対象を所有するAppleアカウント識別子。
    /// - Throws: 削除マーカー保存、CloudKit検索、またはレコード削除に失敗した場合のエラー。
    func deleteSession(
        _ sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws {
        let deletionID = deletionRecordID(
            sessionID: sessionID,
            accountIdentifier: accountIdentifier
        )
        let deletionRecord: CKRecord
        do {
            deletionRecord = try await privateDatabase.record(for: deletionID)
        } catch let error as CKError where error.code == .unknownItem {
            deletionRecord = CKRecord(recordType: Self.deletionRecordType, recordID: deletionID)
        }
        deletionRecord[Self.accountFingerprintKey] = fingerprint(for: accountIdentifier) as CKRecordValue
        deletionRecord[Self.sessionIDKey] = sessionID.rawValue.uuidString.lowercased() as CKRecordValue
        _ = try await privateDatabase.save(deletionRecord)

        try await deleteRecordIfPresent(
            transferRecordID(sessionID: sessionID, accountIdentifier: accountIdentifier)
        )
        let receiptRecords = try await records(
            recordType: Self.receiptRecordType,
            accountIdentifier: accountIdentifier
        )
        for record in receiptRecords where (record[Self.sessionIDKey] as? String)?.caseInsensitiveCompare(
            sessionID.rawValue.uuidString
        ) == .orderedSame {
            try await deleteRecordIfPresent(record.recordID)
        }
    }

    /// 指定アカウントの全セッションAssetとMac受領証をCloudKitから削除します。
    ///
    /// 責務: 1件のアカウントFingerprintに属する全運転データレコードを再試行可能な削除へ変換します。
    /// - Parameter accountIdentifier: 削除対象のAppleアカウント識別子。
    /// - Throws: CloudKit検索またはレコード削除に失敗した場合のエラー。
    func deleteAll(for accountIdentifier: String) async throws {
        let transferRecords = try await records(
            recordType: Self.transferRecordType,
            accountIdentifier: accountIdentifier
        )
        let receiptRecords = try await records(
            recordType: Self.receiptRecordType,
            accountIdentifier: accountIdentifier
        )
        let deletionRecords = try await records(
            recordType: Self.deletionRecordType,
            accountIdentifier: accountIdentifier
        )
        for record in transferRecords + receiptRecords + deletionRecords {
            try await deleteRecordIfPresent(record.recordID)
        }
    }

    /// CloudKitレコードが存在する場合だけ物理削除します。
    ///
    /// 責務: 1件のCloudKitレコードIDを冪等な物理削除結果へ変換します。
    /// - Parameter recordID: 物理削除するCloudKitレコードID。
    /// - Throws: レコード不在以外のCloudKit削除失敗。
    private func deleteRecordIfPresent(_ recordID: CKRecord.ID) async throws {
        do {
            _ = try await privateDatabase.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    /// アカウントFingerprintに一致するCloudKitレコードを全ページ取得します。
    ///
    /// 責務: 1件のレコード種別とアカウントをページング済みCloudKitレコード配列へ変換します。
    /// - Parameters:
    ///   - recordType: 取得するCloudKitレコード種別。
    ///   - accountIdentifier: 絞り込むAppleアカウント識別子。
    /// - Returns: 全ページから取得したCloudKitレコード。
    /// - Throws: CloudKit Queryまたはページ継続取得に失敗した場合のエラー。
    private func records(recordType: String, accountIdentifier: String) async throws -> [CKRecord] {
        let predicate = NSPredicate(
            format: "%K == %@",
            Self.accountFingerprintKey,
            fingerprint(for: accountIdentifier)
        )
        let query = CKQuery(recordType: recordType, predicate: predicate)
        var output: [CKRecord] = []
        var result = try await privateDatabase.records(matching: query)
        output.append(contentsOf: try result.matchResults.map { try $0.1.get() })
        while let cursor = result.queryCursor {
            result = try await privateDatabase.records(continuingMatchFrom: cursor)
            output.append(contentsOf: try result.matchResults.map { try $0.1.get() })
        }
        return output
    }

    /// 利用時点で解決するCloudKit private databaseです。
    private var privateDatabase: CKDatabase {
        (injectedContainer ?? CKContainer.default()).privateCloudDatabase
    }

    /// セッション転送用の安定CloudKitレコードIDを生成します。
    ///
    /// 責務: アカウントとセッションIDを衝突しない転送レコードIDへ変換します。
    /// - Parameters:
    ///   - sessionID: 転送する接続セッションID。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: private database内で安定するレコードID。
    private func transferRecordID(
        sessionID: ConnectionSessionID,
        accountIdentifier: String
    ) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "raw-session-\(fingerprint(for: accountIdentifier))-\(sessionID.rawValue.uuidString.lowercased())"
        )
    }

    /// Mac受領証用の安定CloudKitレコードIDを生成します。
    ///
    /// 責務: アカウント、セッション、Mac識別子を衝突しない受領証レコードIDへ変換します。
    /// - Parameters:
    ///   - sessionID: 取り込んだ接続セッションID。
    ///   - deviceID: 取り込んだMacの安定識別子。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: private database内で安定する受領証レコードID。
    private func receiptRecordID(
        sessionID: ConnectionSessionID,
        deviceID: String,
        accountIdentifier: String
    ) -> CKRecord.ID {
        let deviceFingerprint = sha256(Data(deviceID.utf8))
        return CKRecord.ID(
            recordName: "mac-receipt-\(fingerprint(for: accountIdentifier))-\(sessionID.rawValue.uuidString.lowercased())-\(deviceFingerprint)"
        )
    }

    /// セッション削除マーカー用の安定CloudKitレコードIDを生成します。
    ///
    /// 責務: アカウントとセッションIDを衝突しない削除マーカーIDへ変換します。
    /// - Parameters:
    ///   - sessionID: 物理削除する接続セッションID。
    ///   - accountIdentifier: 削除対象を所有するAppleアカウント識別子。
    /// - Returns: private database内で安定する削除マーカーID。
    private func deletionRecordID(
        sessionID: ConnectionSessionID,
        accountIdentifier: String
    ) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "deleted-session-\(fingerprint(for: accountIdentifier))-\(sessionID.rawValue.uuidString.lowercased())"
        )
    }

    /// Appleアカウント識別子を不可逆の同期スコープへ変換します。
    ///
    /// 責務: 1件のApple識別子から小文字SHA-256を生成します。
    /// - Parameter accountIdentifier: アプリ固有Appleアカウント識別子。
    /// - Returns: 小文字16進表現のSHA-256。
    private func fingerprint(for accountIdentifier: String) -> String {
        sha256(Data(accountIdentifier.utf8))
    }

    /// バイト列のSHA-256を小文字16進表現で返します。
    ///
    /// 責務: 1件のバイト列を転送整合性用の安定Digestへ変換します。
    /// - Parameter data: Digestを計算するバイト列。
    /// - Returns: 小文字16進表現のSHA-256。
    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
