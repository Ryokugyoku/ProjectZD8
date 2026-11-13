import GRDB

/// 同期が読み書きする `sessions` テーブルの1行です。列の値をそのまま保持します。
///
/// `rawAvailability` は端末ローカルの列で、同期しません。
nonisolated struct SyncSessionRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sessions"

    var id: String
    var vehicleID: String
    var startedAt: Int64
    var endedAt: Int64?
    var endReason: String?
    var isDemo: Bool
    var adapterName: String
    var adapterTransport: String
    var platform: String
    var deviceID: String
    var deviceName: String
    var appVersion: String
    var appBuild: String
    var pollingPolicyVersion: Int
    var odometerStartKilometers: Double?
    var odometerEndKilometers: Double?
    var distanceSource: String?
    var sampleCount: Int
    var respondedCount: Int
    var payloadByteCount: Int
    var rawAvailability: String
    var archiveDigest: String?
    var modifiedAt: Int64
    var deletedAt: Int64?

    /// 同期対象(終了済みかつデモ以外)かどうかです。
    var isSyncable: Bool { endedAt != nil && !isDemo }
}
