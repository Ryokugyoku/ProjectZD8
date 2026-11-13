import CloudKit
import Foundation

/// エンジン管理外のアーカイブゾーンへ、`CKDatabase` を直接使ってアーカイブを保存・削除します。
nonisolated struct CloudKitArchiveZoneClient: Sendable {
    private let database: CKDatabase
    private let mapper: CloudKitArchiveRecordMapper
    private let classifier = CloudKitSyncErrorClassifier()

    /// 責務: 指定データベースのアーカイブゾーンを扱うクライアントを生成します。
    init(database: CKDatabase, mapper: CloudKitArchiveRecordMapper = CloudKitArchiveRecordMapper()) {
        self.database = database
        self.mapper = mapper
    }

    /// 責務: アーカイブレコードを保存します。ゾーンが無ければ作ってから保存し直します。
    ///
    /// 同じレコード名で同じ検証値のアーカイブが既にあれば成功とみなします。検証値が違えば上書きします。
    /// - Throws: CloudKitのエラー。
    func upload(sessionID: String, vehicleID: String, digest: String, fileURL: URL) async throws {
        let record = mapper.record(sessionID: sessionID, vehicleID: vehicleID, digest: digest, fileURL: fileURL)
        do {
            try await save(record, policy: .ifServerRecordUnchanged)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            try await ensureZone()
            try await upload(sessionID: sessionID, vehicleID: vehicleID, digest: digest, fileURL: fileURL, zoneEnsured: true)
        } catch let error as CKError where error.code == .serverRecordChanged {
            try await resolveExisting(error, vehicleID: vehicleID, digest: digest, fileURL: fileURL)
        }
    }

    /// 責務: アーカイブレコードをまとめて削除し、セッションIDごとに「サーバーから消えたか」を返します。
    ///
    /// 既に無いもの(レコードやゾーンが無い)は消えたものとして扱います。失敗は投げずに `false` で返します。
    func delete(sessionIDs: [String]) async -> [String: Bool] {
        guard !sessionIDs.isEmpty else { return [:] }
        let ids = sessionIDs.map { mapper.recordID(sessionID: $0) }
        do {
            let result = try await database.modifyRecords(saving: [], deleting: ids, savePolicy: .ifServerRecordUnchanged, atomically: false)
            var outcome: [String: Bool] = [:]
            for id in ids {
                switch result.deleteResults[id] {
                case .success: outcome[id.recordName] = true
                case .failure(let error): outcome[id.recordName] = classifier.isAlreadyGone(error)
                case nil: outcome[id.recordName] = false
                }
            }
            return outcome
        } catch {
            let gone = classifier.isAlreadyGone(error)
            return Dictionary(uniqueKeysWithValues: sessionIDs.map { ($0, gone) })
        }
    }

    // MARK: - 内部

    /// 責務: ゾーン作成後の1回だけの再試行です。
    private func upload(sessionID: String, vehicleID: String, digest: String, fileURL: URL, zoneEnsured: Bool) async throws {
        let record = mapper.record(sessionID: sessionID, vehicleID: vehicleID, digest: digest, fileURL: fileURL)
        do {
            try await save(record, policy: .ifServerRecordUnchanged)
        } catch let error as CKError where error.code == .serverRecordChanged {
            try await resolveExisting(error, vehicleID: vehicleID, digest: digest, fileURL: fileURL)
        }
    }

    /// 責務: 既存のアーカイブとの競合を解決します。同じ検証値なら成功、違えばサーバーの版へ上書き保存します。
    private func resolveExisting(_ error: CKError, vehicleID: String, digest: String, fileURL: URL) async throws {
        guard let server = error.serverRecord else { throw error }
        if CloudKitArchiveRecordMapper.isSameArchive(server, digest: digest) { return }
        mapper.apply(to: server, vehicleID: vehicleID, digest: digest, fileURL: fileURL)
        try await save(server, policy: .allKeys)
    }

    /// 責務: アーカイブゾーンを作成します。
    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: mapper.zoneID)
        let result = try await database.modifyRecordZones(saving: [zone], deleting: [])
        if case .failure(let error) = result.saveResults[zone.zoneID] { throw error }
    }

    /// 責務: 1件のレコードを保存し、レコード単位の失敗も投げます。
    private func save(_ record: CKRecord, policy: CKModifyRecordsOperation.RecordSavePolicy) async throws {
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: policy, atomically: false)
        if case .failure(let error) = result.saveResults[record.recordID] { throw error }
    }
}
