import GRDB

/// 取得runtimeと確定状態を保持するmanifest親行です。
struct ConnectionSessionAcquisitionManifestRecord: Codable, FetchableRecord, PersistableRecord {
    /// manifest親テーブル名です。
    static let databaseTableName = "connection_session_acquisition_manifests"

    /// 親接続セッションIDです。
    let sessionID: String
    /// manifest構造versionです。
    let manifestVersion: Int
    /// ユーザー向けアプリversionです。
    let applicationMarketingVersion: String
    /// 配布build versionです。
    let applicationBuildVersion: String
    /// 保存schema契約versionです。
    let schemaContractVersion: Int
    /// polling方針versionです。
    let pollingPolicyVersion: Int
    /// 取得platformです。
    let acquisitionPlatform: String
    /// model入力manifest versionです。
    let modelInputManifestVersion: Int
    /// aggregateが確定済みかどうかです。
    let isSealed: Bool
}
