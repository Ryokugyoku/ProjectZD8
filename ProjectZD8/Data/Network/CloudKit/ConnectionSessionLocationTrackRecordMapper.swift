import CloudKit
import Foundation

/// 軌跡の CloudKit レコードと値を相互に変換し、recordName を決めます。
///
/// `CKRecord` はコンテナ無しで作れるので、この型は CloudKit に接続せずに検証できます。
nonisolated struct ConnectionSessionLocationTrackRecordMapper: Sendable {
    /// 軌跡のレコードタイプです(Raw の `ConnectionSessionRawLog` とは別)。
    static let recordType = "ConnectionSessionLocationTrack"
    /// 所有アカウントの fingerprint のフィールドです(Queryable)。
    static let accountFingerprintKey: CKRecord.FieldKey = "accountFingerprint"
    /// セッションの小文字 UUID のフィールドです。
    static let sessionIDKey: CKRecord.FieldKey = "sessionID"
    /// ペイロードの形式の版のフィールドです。
    static let payloadFormatVersionKey: CKRecord.FieldKey = "payloadFormatVersion"
    /// Asset のバイト列の SHA-256 のフィールドです。
    static let manifestDigestKey: CKRecord.FieldKey = "manifestDigest"
    /// サンプルの件数のフィールドです。
    static let sampleCountKey: CKRecord.FieldKey = "sampleCount"
    /// 事象の件数のフィールドです。
    static let eventCountKey: CKRecord.FieldKey = "eventCount"
    /// ペイロードの Asset のフィールドです。
    static let payloadAssetKey: CKRecord.FieldKey = "payloadAsset"
    /// Asset を除いた、概要を読むのに要るフィールドです。
    static let manifestKeys: [CKRecord.FieldKey] = [
        accountFingerprintKey, sessionIDKey, payloadFormatVersionKey, manifestDigestKey, sampleCountKey, eventCountKey
    ]

    /// 既定の構成で作ります。
    ///
    /// 責務: 状態を持たない変換器を用意します。
    init() {}

    /// セッションとアカウントから決まるレコード ID を返します。
    ///
    /// 責務: `location-track-<fingerprint>-<小文字セッションUUID>` の recordName を作ります。
    /// - Parameters:
    ///   - sessionID: 軌跡のセッション。
    ///   - accountFingerprint: 所有アカウントの fingerprint。
    /// - Returns: 再送でも同じになるレコード ID。
    func recordID(sessionID: ConnectionSessionID, accountFingerprint: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "location-track-\(accountFingerprint)-\(sessionID.rawValue.uuidString.lowercased())")
    }

    /// 保存する新しいレコードを作ります。
    ///
    /// 責務: 7つのフィールドを埋めたレコードを、毎回新しく組み立てます。
    /// - Parameters:
    ///   - sessionID: 軌跡のセッション。
    ///   - accountFingerprint: 所有アカウントの fingerprint。
    ///   - digest: Asset のバイト列の SHA-256。
    ///   - sampleCount: サンプルの件数。
    ///   - eventCount: 事象の件数。
    ///   - assetURL: Asset にするファイルの場所。
    /// - Returns: 保存するレコード。
    func makeRecord(
        sessionID: ConnectionSessionID,
        accountFingerprint: String,
        digest: String,
        sampleCount: Int,
        eventCount: Int,
        assetURL: URL
    ) -> CKRecord {
        let record = CKRecord(
            recordType: Self.recordType,
            recordID: recordID(sessionID: sessionID, accountFingerprint: accountFingerprint)
        )
        record[Self.accountFingerprintKey] = accountFingerprint as CKRecordValue
        record[Self.sessionIDKey] = sessionID.rawValue.uuidString.lowercased() as CKRecordValue
        record[Self.payloadFormatVersionKey] = NSNumber(value: ConnectionSessionLocationTrackPayload.currentFormatVersion)
        record[Self.manifestDigestKey] = digest as CKRecordValue
        record[Self.sampleCountKey] = NSNumber(value: Int64(sampleCount))
        record[Self.eventCountKey] = NSNumber(value: Int64(eventCount))
        record[Self.payloadAssetKey] = CKAsset(fileURL: assetURL)
        return record
    }

    /// レコードから Asset を除いた概要を読みます。
    ///
    /// 責務: タイプ・所有関係・版を確かめてから、digest と件数を読みます。
    /// - Parameters:
    ///   - record: 読むレコード。
    ///   - expectedSessionID: 求めたセッション。`nil` ならセッションは比べません。
    ///   - accountFingerprint: 自分のアカウントの fingerprint。
    /// - Returns: 概要。
    /// - Throws: 版が新しすぎる場合は `ConnectionSessionLocationTrackCloudError.unsupportedPayloadFormat`。
    ///   タイプ・fingerprint・セッションの不一致、必須フィールドの欠落や型違い、digest の形式不正は `.integrityConflict`。
    func manifest(
        from record: CKRecord,
        expectedSessionID: ConnectionSessionID?,
        accountFingerprint: String
    ) throws -> ConnectionSessionLocationTrackRemoteManifest {
        let sessionID = try ownedSessionID(from: record, accountFingerprint: accountFingerprint)
        if let expectedSessionID, expectedSessionID != sessionID {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        try validateFormatVersion(of: record)
        guard let digest = record[Self.manifestDigestKey] as? String, Self.isSHA256Hex(digest),
              let sampleCount = Self.count(in: record, key: Self.sampleCountKey),
              let eventCount = Self.count(in: record, key: Self.eventCountKey) else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return ConnectionSessionLocationTrackRemoteManifest(
            sessionID: sessionID,
            manifestDigest: digest,
            sampleCount: sampleCount,
            eventCount: eventCount
        )
    }

    /// 自分のアカウントの軌跡レコードから、セッション ID を読みます。
    ///
    /// 責務: タイプと fingerprint を確かめ、`sessionID` フィールドを UUID として読みます。版は確かめません。
    /// - Parameters:
    ///   - record: 読むレコード。
    ///   - accountFingerprint: 自分のアカウントの fingerprint。
    /// - Returns: セッション ID。
    /// - Throws: タイプ・fingerprint の不一致、セッション ID の欠落や形式不正は `.integrityConflict`。
    func ownedSessionID(from record: CKRecord, accountFingerprint: String) throws -> ConnectionSessionID {
        guard isOwnedTrackRecord(record, accountFingerprint: accountFingerprint),
              let text = record[Self.sessionIDKey] as? String,
              let uuid = UUID(uuidString: text) else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return ConnectionSessionID(rawValue: uuid)
    }

    /// レコードが軌跡のタイプで、指定アカウントのものかを返します。
    ///
    /// 責務: レコードタイプと `accountFingerprint` フィールドを比べます。
    /// - Parameters:
    ///   - record: 確かめるレコード。
    ///   - accountFingerprint: 自分のアカウントの fingerprint。
    /// - Returns: 両方が一致すれば true。
    func isOwnedTrackRecord(_ record: CKRecord, accountFingerprint: String) -> Bool {
        record.recordType == Self.recordType
            && record[Self.accountFingerprintKey] as? String == accountFingerprint
    }

    /// レコードの Asset のファイルの場所を返します。
    ///
    /// 責務: `payloadAsset` が Asset で、ファイルの場所を持つことを確かめます。
    /// - Parameter record: Asset を含めて取得したレコード。
    /// - Returns: Asset のファイルの場所。
    /// - Throws: Asset または場所が無い場合は `.integrityConflict`。
    func payloadAssetURL(from record: CKRecord) throws -> URL {
        guard let asset = record[Self.payloadAssetKey] as? CKAsset, let url = asset.fileURL else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return url
    }

    /// レコードの形式の版が、この版で読めるものかを確かめます。
    ///
    /// 責務: 版が無い・型違い・現行より古い場合と、現行より新しい場合を区別して失敗にします。
    /// - Parameter record: 確かめるレコード。
    /// - Throws: 新しすぎる版は `.unsupportedPayloadFormat`、それ以外の不一致は `.integrityConflict`。
    private func validateFormatVersion(of record: CKRecord) throws {
        guard let version = (record[Self.payloadFormatVersionKey] as? NSNumber)?.int64Value else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        guard version <= ConnectionSessionLocationTrackPayload.currentFormatVersion else {
            throw ConnectionSessionLocationTrackCloudError.unsupportedPayloadFormat(version: version)
        }
        guard version == ConnectionSessionLocationTrackPayload.currentFormatVersion else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
    }

    /// 件数のフィールドを 0 以上の Int として読みます。
    ///
    /// 責務: 数値でない・負・Int に収まらない値を `nil` にします。
    /// - Parameters:
    ///   - record: 読むレコード。
    ///   - key: 件数のフィールド。
    /// - Returns: 件数。読めなければ `nil`。
    private static func count(in record: CKRecord, key: CKRecord.FieldKey) -> Int? {
        guard let value = (record[key] as? NSNumber)?.int64Value, value >= 0 else {
            return nil
        }
        return Int(exactly: value)
    }

    /// 文字列が小文字16進64文字の SHA-256 かを返します。
    ///
    /// 責務: 長さと文字種(0-9, a-f)を判定します。
    /// - Parameter text: 確かめる文字列。
    /// - Returns: 形式どおりなら true。
    private static func isSHA256Hex(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }
}
