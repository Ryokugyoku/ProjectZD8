import CloudKit
import Foundation

/// 軌跡を CloudKit の private database へ保存・取得・削除します。
///
/// 1セッションの軌跡は1件のレコード(`ConnectionSessionLocationTrackRecordMapper.recordType`)で、本体は Asset に入れます。
/// 保存は毎回新しいレコードを作って全フィールドで上書きします。ストアのエラーは包まずに投げ直します
/// (`CloudKitAccountDeletionFailureClassifier` が `CKError` の型で分類するため)。
/// 大きな軌跡の符号化・復号と digest の計算は、メインスレッドを塞がないようにメイン外で行います。
@MainActor
final class CloudKitConnectionSessionLocationTrackRepository: ConnectionSessionLocationTrackCloudRepository {
    /// CloudKit の private database を表す口です。
    private let store: any CloudKitPrivateRecordStore
    /// Asset 用の一時ファイルを扱う境界です。
    private let fileManager: FileManager
    /// 軌跡と Asset のバイト列を変換する Codec です。
    private let codec: ConnectionSessionLocationTrackPayloadCodec
    /// レコードと値を変換する変換器です。
    private let mapper: ConnectionSessionLocationTrackRecordMapper

    /// 依存を固定して作ります。
    ///
    /// 責務: ストア・一時ファイル・Codec・変換器を1つのリポジトリへ結び付けます。CloudKit にはまだ触れません。
    /// - Parameters:
    ///   - store: private database を表す口。
    ///   - fileManager: Asset 用の一時ファイルを扱う境界。
    ///   - codec: 軌跡の Codec。
    ///   - mapper: レコードの変換器。
    init(
        store: any CloudKitPrivateRecordStore = CKDatabasePrivateRecordStore(),
        fileManager: FileManager = .default,
        codec: ConnectionSessionLocationTrackPayloadCodec = .init(),
        mapper: ConnectionSessionLocationTrackRecordMapper = .init()
    ) {
        self.store = store
        self.fileManager = fileManager
        self.codec = codec
        self.mapper = mapper
    }

    /// 軌跡を保存します。
    ///
    /// 責務: 符号化したバイト列を一時ファイル経由で Asset にし、同じ recordName へ上書きします。一時ファイルは必ず消します。
    /// - Parameters:
    ///   - track: 送る軌跡。
    ///   - accountIdentifier: 対象アカウント。
    /// - Returns: Asset に入れたバイト列の SHA-256。
    /// - Throws: 空の軌跡は `.invalidState`(何も保存しません)。一時ファイルや CloudKit の失敗はそのまま。
    func upload(_ track: ConnectionSessionLocationTrack, for accountIdentifier: String) async throws -> String {
        guard track.isEmpty == false else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        let fingerprint = CloudKitRecordDigest.accountFingerprint(for: accountIdentifier)
        let (data, digest) = try await Self.encode(track, accountFingerprint: fingerprint, codec: codec)
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("location-track-\(UUID().uuidString).lzfse")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)
        let record = mapper.makeRecord(
            sessionID: track.sessionID,
            accountFingerprint: fingerprint,
            digest: digest,
            sampleCount: track.samples.count,
            eventCount: track.events.count,
            assetURL: temporaryURL
        )
        try await store.overwrite(record)
        return digest
    }

    /// Asset を取得せずにレコードの概要を返します。
    ///
    /// 責務: `payloadAsset` を除いたフィールドだけを取得し、概要として検証します。
    /// - Parameters:
    ///   - sessionID: 対象のセッション。
    ///   - accountIdentifier: 対象アカウント。
    /// - Returns: 概要。レコードが無ければ `nil`。
    /// - Throws: 検証の失敗は `.integrityConflict` か `.unsupportedPayloadFormat`。CloudKit の失敗はそのまま。
    func remoteManifest(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws -> ConnectionSessionLocationTrackRemoteManifest? {
        let fingerprint = CloudKitRecordDigest.accountFingerprint(for: accountIdentifier)
        guard let record = try await store.record(
            for: mapper.recordID(sessionID: sessionID, accountFingerprint: fingerprint),
            desiredKeys: ConnectionSessionLocationTrackRecordMapper.manifestKeys
        ) else {
            return nil
        }
        return try mapper.manifest(from: record, expectedSessionID: sessionID, accountFingerprint: fingerprint)
    }

    /// 軌跡を取得して検証します。
    ///
    /// 責務: 概要を検証し、Asset のバイト列の digest・内容・件数がすべて一致した場合だけ軌跡を返します。
    /// - Parameters:
    ///   - sessionID: 対象のセッション。
    ///   - accountIdentifier: 対象アカウント。
    /// - Returns: 検証済みの軌跡。レコードが無ければ `nil`。
    /// - Throws: Asset の欠落、digest・件数の不一致、内容の検証の失敗は `.integrityConflict`。
    ///   新しすぎる版は `.unsupportedPayloadFormat`。CloudKit と Asset の読み込みの失敗はそのまま。
    func download(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws -> VerifiedConnectionSessionLocationTrack? {
        let fingerprint = CloudKitRecordDigest.accountFingerprint(for: accountIdentifier)
        guard let record = try await store.record(
            for: mapper.recordID(sessionID: sessionID, accountFingerprint: fingerprint),
            desiredKeys: nil
        ) else {
            return nil
        }
        let manifest = try mapper.manifest(from: record, expectedSessionID: sessionID, accountFingerprint: fingerprint)
        let track = try await Self.verifiedTrack(
            assetURL: try mapper.payloadAssetURL(from: record),
            manifest: manifest,
            accountFingerprint: fingerprint,
            codec: codec
        )
        return VerifiedConnectionSessionLocationTrack(track: track, manifestDigest: manifest.manifestDigest)
    }

    /// iCloud にある自分の軌跡のセッション ID を返します。
    ///
    /// 責務: 自分の fingerprint のレコードを Asset 無しで全件取得し、セッション ID の集合にします。
    /// - Parameter accountIdentifier: 対象アカウント。
    /// - Returns: セッション ID の集合。
    /// - Throws: セッション ID を読めないレコードは `.integrityConflict`。CloudKit の失敗はそのまま。
    func remoteSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID> {
        let fingerprint = CloudKitRecordDigest.accountFingerprint(for: accountIdentifier)
        let records = try await ownedRecords(
            accountFingerprint: fingerprint,
            desiredKeys: [
                ConnectionSessionLocationTrackRecordMapper.accountFingerprintKey,
                ConnectionSessionLocationTrackRecordMapper.sessionIDKey
            ]
        )
        return try Set(records.map { try mapper.ownedSessionID(from: $0, accountFingerprint: fingerprint) })
    }

    /// 1セッションの軌跡を削除します。
    ///
    /// 責務: 決まったレコード ID を削除し、無くても成功とします(冪等)。
    /// - Parameters:
    ///   - sessionID: 対象のセッション。
    ///   - accountIdentifier: 対象アカウント。
    /// - Throws: レコード不在以外の CloudKit の失敗はそのまま。
    func delete(sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {
        let fingerprint = CloudKitRecordDigest.accountFingerprint(for: accountIdentifier)
        try await store.deleteRecordIfPresent(mapper.recordID(sessionID: sessionID, accountFingerprint: fingerprint))
    }

    /// 自分のアカウントの軌跡をすべて削除します。
    ///
    /// 責務: 自分の fingerprint の軌跡レコードを Asset 無しで列挙し、1件ずつ削除します。
    /// - Parameter accountIdentifier: 対象アカウント。
    /// - Throws: CloudKit の失敗はそのまま(途中で失敗しても、再試行で残りを消せます)。
    func deleteAll(for accountIdentifier: String) async throws {
        let fingerprint = CloudKitRecordDigest.accountFingerprint(for: accountIdentifier)
        let records = try await ownedRecords(
            accountFingerprint: fingerprint,
            desiredKeys: [ConnectionSessionLocationTrackRecordMapper.accountFingerprintKey]
        )
        for record in records {
            try await store.deleteRecordIfPresent(record.recordID)
        }
    }

    /// 自分のアカウントの軌跡レコードを全件取得します。
    ///
    /// 責務: タイプと fingerprint で絞ったクエリの結果から、軌跡のタイプで自分のものだけを残します。
    /// - Parameters:
    ///   - accountFingerprint: 自分のアカウントの fingerprint。
    ///   - desiredKeys: 取得するフィールド(Asset は含めません)。
    /// - Returns: 自分の軌跡レコード。
    /// - Throws: CloudKit の失敗はそのまま。
    private func ownedRecords(
        accountFingerprint: String,
        desiredKeys: [CKRecord.FieldKey]
    ) async throws -> [CKRecord] {
        let records = try await store.records(
            ofType: ConnectionSessionLocationTrackRecordMapper.recordType,
            whereField: ConnectionSessionLocationTrackRecordMapper.accountFingerprintKey,
            equals: accountFingerprint,
            desiredKeys: desiredKeys
        )
        return records.filter { mapper.isOwnedTrackRecord($0, accountFingerprint: accountFingerprint) }
    }

    /// 軌跡を符号化し、その digest を計算します。メイン外で実行します。
    ///
    /// 責務: 大きな軌跡の JSON 化・圧縮・SHA-256 を、メインスレッドを塞がずに行います。
    /// - Parameters:
    ///   - track: 符号化する軌跡。
    ///   - accountFingerprint: 所有アカウントの fingerprint。
    ///   - codec: 使う Codec。
    /// - Returns: Asset に入れるバイト列と、その SHA-256。
    /// - Throws: Codec の失敗。
    @concurrent
    private nonisolated static func encode(
        _ track: ConnectionSessionLocationTrack,
        accountFingerprint: String,
        codec: ConnectionSessionLocationTrackPayloadCodec
    ) async throws -> (data: Data, digest: String) {
        let data = try codec.encode(track, accountFingerprint: accountFingerprint)
        return (data, CloudKitRecordDigest.sha256Hex(data))
    }

    /// Asset のバイト列を読み、digest・内容・件数を検証して軌跡を返します。メイン外で実行します。
    ///
    /// 責務: 読み込み・SHA-256・伸長・JSON の読み取りを、メインスレッドを塞がずに行います。
    /// - Parameters:
    ///   - assetURL: Asset のファイルの場所。
    ///   - manifest: 検証済みのレコードの概要。
    ///   - accountFingerprint: 自分のアカウントの fingerprint。
    ///   - codec: 使う Codec。
    /// - Returns: 検証済みの軌跡。
    /// - Throws: digest・件数の不一致は `.integrityConflict`。読み込みと Codec の失敗はそのまま。
    @concurrent
    private nonisolated static func verifiedTrack(
        assetURL: URL,
        manifest: ConnectionSessionLocationTrackRemoteManifest,
        accountFingerprint: String,
        codec: ConnectionSessionLocationTrackPayloadCodec
    ) async throws -> ConnectionSessionLocationTrack {
        let data = try Data(contentsOf: assetURL)
        guard CloudKitRecordDigest.sha256Hex(data) == manifest.manifestDigest else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        let track = try codec.decode(
            data,
            expectedSessionID: manifest.sessionID,
            expectedAccountFingerprint: accountFingerprint
        )
        guard track.samples.count == manifest.sampleCount, track.events.count == manifest.eventCount else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return track
    }
}
