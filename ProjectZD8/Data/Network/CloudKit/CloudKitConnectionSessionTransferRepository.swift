import CloudKit
import CryptoKit
import Foundation

/// CloudKit private databaseで接続セッションAssetとMac取込受領証を交換します。
@MainActor
final class CloudKitConnectionSessionTransferRepository: ConnectionSessionTransferRepository {
    /// セッションPayloadを保持するCloudKitレコード種別です。
    private static let transferRecordType = "ConnectionSessionRawLog"
    /// Raw Payloadを含まないセッション概要のCloudKitレコード種別です。
    private static let metadataRecordType = "ConnectionSessionMetadata"
    /// Mac取込受領証を保持するCloudKitレコード種別です。
    private static let receiptRecordType = "ConnectionSessionMacReceipt"
    /// 全端末へセッション物理削除を伝えるCloudKitレコード種別です。
    private static let deletionRecordType = "ConnectionSessionDeletion"
    /// セッションPayload Assetのフィールド名です。
    private static let payloadAssetKey = "payloadAsset"
    /// 符号化済みセッション概要のフィールド名です。
    private static let metadataDataKey = "metadataData"
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

    /// Raw Payloadを含まないセッション概要をCloudKitへ保存します。
    ///
    /// 責務: 1件のセッション概要を決定的JSON付きCloudKitレコードへ変換します。
    /// - Parameters:
    ///   - metadata: 一覧共有に必要なセッション概要とRaw Manifest。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Throws: 状態検証、符号化、またはCloudKit保存に失敗した場合のエラー。
    func publishMetadata(
        _ metadata: ConnectionSessionCloudMetadata,
        for accountIdentifier: String
    ) async throws {
        guard metadata.session.endedAt != nil,
              metadata.session.accountIdentifier == accountIdentifier,
              metadata.manifestDigest.isEmpty == false else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        let id = metadataRecordID(
            sessionID: metadata.session.id,
            accountIdentifier: accountIdentifier
        )
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.metadataRecordType, recordID: id)
        }
        record[Self.accountFingerprintKey] = fingerprint(for: accountIdentifier) as CKRecordValue
        record[Self.sessionIDKey] = metadata.session.id.rawValue.uuidString.lowercased() as CKRecordValue
        record[Self.manifestDigestKey] = metadata.manifestDigest as CKRecordValue
        record[Self.metadataDataKey] = try encoder.encode(metadata) as CKRecordValue
        record["endedAt"] = metadata.session.endedAt as CKRecordValue?
        _ = try await privateDatabase.save(record)
    }

    /// 指定アカウントの軽量概要を取得し旧Rawレコードだけのセッションを一度だけ移行します。
    ///
    /// 責務: CloudKit概要レコードと未移行旧PayloadをRaw非包含セッション一覧へ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: Raw Payloadを含まないセッション概要。
    /// - Throws: CloudKit取得、旧Payload移行、復号、または整合性検証に失敗した場合のエラー。
    func downloadMetadata(for accountIdentifier: String) async throws -> [ConnectionSessionCloudMetadata] {
        let metadataRecords = try await records(
            recordType: Self.metadataRecordType,
            accountIdentifier: accountIdentifier,
            desiredKeys: [Self.sessionIDKey, Self.manifestDigestKey, Self.metadataDataKey]
        )
        var metadataByID: [ConnectionSessionID: ConnectionSessionCloudMetadata] = [:]
        for record in metadataRecords {
            guard let data = record[Self.metadataDataKey] as? Data else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            let metadata = try decoder.decode(ConnectionSessionCloudMetadata.self, from: data)
            guard metadata.session.accountIdentifier == accountIdentifier,
                  metadata.manifestDigest == record[Self.manifestDigestKey] as? String,
                  metadata.session.id.rawValue.uuidString.caseInsensitiveCompare(
                    record[Self.sessionIDKey] as? String ?? ""
                  ) == .orderedSame else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            if let existing = metadataByID[metadata.session.id], existing != metadata {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            metadataByID[metadata.session.id] = metadata
        }

        let manifests = try await downloadTransferManifests(for: accountIdentifier)
        for sessionID in manifests.keys where metadataByID[sessionID] == nil {
            let transfer = try await downloadTransfer(sessionID: sessionID, for: accountIdentifier)
            let metadata = ConnectionSessionCloudMetadata(
                session: transfer.package.session,
                manifestDigest: transfer.manifestDigest
            )
            try await publishMetadata(metadata, for: accountIdentifier)
            metadataByID[sessionID] = metadata
        }
        return Array(metadataByID.values)
    }

    /// Raw Assetを取得せずCloudKit上のセッション別Manifestを復元します。
    ///
    /// 責務: 指定アカウントのRaw転送レコードをセッション別Manifest辞書へ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: セッションIDをキーとするRaw Payload Manifest。
    /// - Throws: CloudKit取得、必須フィールド復元、または重複競合に失敗した場合のエラー。
    func downloadTransferManifests(
        for accountIdentifier: String
    ) async throws -> [ConnectionSessionID: String] {
        let transferRecords = try await records(
            recordType: Self.transferRecordType,
            accountIdentifier: accountIdentifier,
            desiredKeys: [Self.sessionIDKey, Self.manifestDigestKey]
        )
        var manifests: [ConnectionSessionID: String] = [:]
        for record in transferRecords {
            guard let sessionIDString = record[Self.sessionIDKey] as? String,
                  let uuid = UUID(uuidString: sessionIDString),
                  let digest = record[Self.manifestDigestKey] as? String else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            let sessionID = ConnectionSessionID(rawValue: uuid)
            if let existing = manifests[sessionID], existing != digest {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            manifests[sessionID] = digest
        }
        return manifests
    }

    /// 指定セッションのRaw Assetを取得してDigestを検証します。
    ///
    /// 責務: 1件のCloudKit Raw転送レコードを検証済みセッションPayloadへ変換します。
    /// - Parameters:
    ///   - sessionID: Raw Payloadを取得するセッションID。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: Asset SHA-256が保存済みManifestと一致した転送Payload。
    /// - Throws: CloudKit取得、Asset読込、Digest検証、または復号に失敗した場合のエラー。
    func downloadTransfer(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws -> VerifiedConnectionSessionTransfer {
        let record = try await privateDatabase.record(
            for: transferRecordID(sessionID: sessionID, accountIdentifier: accountIdentifier)
        )
        return try verifiedTransfer(from: record, accountIdentifier: accountIdentifier)
    }

    /// 指定セッションのRaw AssetをCloudKit進捗通知付きで取得してDigestを検証します。
    ///
    /// 責務: 1件のCloudKit Raw転送レコードをAsset取得率と検証済みセッションPayloadへ変換します。
    /// - Parameters:
    ///   - sessionID: Raw Payloadを取得するセッションID。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    ///   - progress: `0.0...1.0` の範囲で通知するAsset取得進捗。
    /// - Returns: Asset SHA-256が保存済みManifestと一致した転送Payload。
    /// - Throws: CloudKit取得、Asset読込、Digest検証、または復号に失敗した場合のエラー。
    func downloadTransfer(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> VerifiedConnectionSessionTransfer {
        progress(0)
        let record = try await record(
            for: transferRecordID(sessionID: sessionID, accountIdentifier: accountIdentifier),
            progress: progress
        )
        let transfer = try verifiedTransfer(from: record, accountIdentifier: accountIdentifier)
        progress(1)
        return transfer
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
        try await upload(package, for: accountIdentifier, progress: { _ in })
    }

    /// 終了済みセッションPayloadを進捗通知付きCloudKit Assetへ保存します。
    ///
    /// 責務: 1件のセッションPayloadをCloudKit保存率とSHA-256付きレコードへ変換します。
    /// - Parameters:
    ///   - package: 保存するセッションと未デコードRawログ。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    ///   - progress: `0.0...1.0` の範囲で通知するAsset保存進捗。
    /// - Returns: 保存したAssetバイトのSHA-256。
    /// - Throws: 状態検証、符号化、一時ファイル、またはCloudKit保存に失敗した場合のエラー。
    func upload(
        _ package: ConnectionSessionTransferPackage,
        for accountIdentifier: String,
        progress: @escaping @MainActor (Double) -> Void
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
        progress(0)
        _ = try await save(record, progress: progress)
        progress(1)
        try await publishMetadata(
            ConnectionSessionCloudMetadata(session: package.session, manifestDigest: digest),
            for: accountIdentifier
        )
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
        return try records.map { try verifiedTransfer(from: $0, accountIdentifier: accountIdentifier) }
    }

    /// CloudKitレコードのAsset、Digest、所有関係を検証して転送Payloadを返します。
    ///
    /// 責務: 1件のRaw転送レコードを整合性検証済みDomain転送へ変換します。
    /// - Parameters:
    ///   - record: 検証するCloudKit Raw転送レコード。
    ///   - accountIdentifier: 期待するAppleアカウント識別子。
    /// - Returns: Assetと識別情報を検証したセッション転送。
    /// - Throws: Asset不在、Digest不一致、復号失敗、または所有関係不一致。
    private func verifiedTransfer(
        from record: CKRecord,
        accountIdentifier: String
    ) throws -> VerifiedConnectionSessionTransfer {
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
        return VerifiedConnectionSessionTransfer(package: package, manifestDigest: expectedDigest)
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
        try await deleteRecordIfPresent(
            metadataRecordID(sessionID: sessionID, accountIdentifier: accountIdentifier)
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

    /// 指定アカウントの全セッション概要、Raw Asset、Mac受領証、および削除マーカーをCloudKitから削除します。
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
        let metadataRecords = try await records(
            recordType: Self.metadataRecordType,
            accountIdentifier: accountIdentifier
        )
        for record in transferRecords + metadataRecords + receiptRecords + deletionRecords {
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
    ///   - desiredKeys: Asset取得を避ける場合に限定するフィールド名。
    /// - Returns: 全ページから取得したCloudKitレコード。
    /// - Throws: CloudKit Queryまたはページ継続取得に失敗した場合のエラー。
    private func records(
        recordType: String,
        accountIdentifier: String,
        desiredKeys: [CKRecord.FieldKey]? = nil
    ) async throws -> [CKRecord] {
        let predicate = NSPredicate(
            format: "%K == %@",
            Self.accountFingerprintKey,
            fingerprint(for: accountIdentifier)
        )
        let query = CKQuery(recordType: recordType, predicate: predicate)
        var output: [CKRecord] = []
        var result = try await privateDatabase.records(
            matching: query,
            desiredKeys: desiredKeys
        )
        output.append(contentsOf: try result.matchResults.map { try $0.1.get() })
        while let cursor = result.queryCursor {
            result = try await privateDatabase.records(continuingMatchFrom: cursor)
            output.append(contentsOf: try result.matchResults.map { try $0.1.get() })
        }
        return output
    }

    /// 1件のCloudKitレコードとAssetを取得率通知付きで取得します。
    ///
    /// 責務: 1件のレコードIDをCloudKit取得操作の進捗と完了レコードへ変換します。
    /// - Parameters:
    ///   - recordID: 取得するCloudKitレコードID。
    ///   - progress: `0.0...1.0` の範囲で通知するAsset取得進捗。
    /// - Returns: Assetを含めて取得したCloudKitレコード。
    /// - Throws: CloudKitがレコードまたはAssetを取得できない場合のエラー。
    private func record(
        for recordID: CKRecord.ID,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> CKRecord {
        let operation = CKFetchRecordsOperation(recordIDs: [recordID])
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var fetchedResult: Result<CKRecord, Error>?
                operation.perRecordProgressBlock = { fetchedRecordID, value in
                    guard fetchedRecordID == recordID else { return }
                    Task { @MainActor in progress(value) }
                }
                operation.perRecordResultBlock = { fetchedRecordID, result in
                    guard fetchedRecordID == recordID else { return }
                    fetchedResult = result
                }
                operation.fetchRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        guard let fetchedResult else {
                            continuation.resume(throwing: ConnectionSessionRepositoryError.invalidState)
                            return
                        }
                        continuation.resume(with: fetchedResult)
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
                privateDatabase.add(operation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    /// 1件のCloudKitレコードをAsset保存率通知付きで保存します。
    ///
    /// 責務: 1件のCloudKitレコードを保存進捗と完了レコードへ変換します。
    /// - Parameters:
    ///   - record: Assetを含む保存対象レコード。
    ///   - progress: `0.0...1.0` の範囲で通知するAsset保存進捗。
    /// - Returns: CloudKitが保存したレコード。
    /// - Throws: CloudKitがレコードまたはAssetを保存できない場合のエラー。
    private func save(
        _ record: CKRecord,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> CKRecord {
        let operation = CKModifyRecordsOperation(recordsToSave: [record])
        operation.savePolicy = .changedKeys
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var savedResult: Result<CKRecord, Error>?
                operation.perRecordProgressBlock = { recordID, value in
                    guard recordID == record.recordID else { return }
                    Task { @MainActor in progress(value) }
                }
                operation.perRecordSaveBlock = { recordID, result in
                    guard recordID == record.recordID else { return }
                    savedResult = result
                }
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        guard let savedResult else {
                            continuation.resume(throwing: ConnectionSessionRepositoryError.invalidState)
                            return
                        }
                        continuation.resume(with: savedResult)
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
                privateDatabase.add(operation)
            }
        } onCancel: {
            operation.cancel()
        }
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

    /// セッション概要用の安定CloudKitレコードIDを生成します。
    ///
    /// 責務: アカウントとセッションIDを衝突しない概要レコードIDへ変換します。
    /// - Parameters:
    ///   - sessionID: 概要を共有する接続セッションID。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: private database内で安定する概要レコードID。
    private func metadataRecordID(
        sessionID: ConnectionSessionID,
        accountIdentifier: String
    ) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "session-metadata-\(fingerprint(for: accountIdentifier))-\(sessionID.rawValue.uuidString.lowercased())"
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
