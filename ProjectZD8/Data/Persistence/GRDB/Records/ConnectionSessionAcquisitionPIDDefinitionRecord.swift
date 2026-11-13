import GRDB

/// 1件の取得時PID定義を保持する永続化行です。
struct ConnectionSessionAcquisitionPIDDefinitionRecord: Codable, FetchableRecord, PersistableRecord {
    /// PID定義snapshotテーブル名です。
    static let databaseTableName = "connection_session_acquisition_pid_definitions"

    /// 親接続セッションIDです。
    let sessionID: String
    /// OBD Service番号です。
    let service: Int
    /// Service内PID番号です。
    let pid: Int
    /// 取得時の対応状態です。
    let capabilitySupport: String
    /// 継続収集対象かどうかです。
    let isCollectionEnabled: Bool
    /// 取得時定義revisionです。
    let definitionRevision: Int
    /// 式評価に必要なbyte数です。
    let requiredByteCount: Int
    /// 式のcanonicalization契約versionです。
    let formulaCanonicalizationVersion: Int
    /// 取得時の完全な式文字列です。
    let formulaExpression: String
    /// 取得時の単位です。
    let unit: String
    /// 有効範囲の種類です。
    let validityRangeKind: String
    /// 閉区間の下限です。
    let minimumValue: Double?
    /// 閉区間の上限です。
    let maximumValue: Double?
}
