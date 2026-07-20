import Foundation

/// 端末内Rawログの保管状態です。
enum ConnectionSessionLocalRawState: String, Codable, Equatable, Sendable {
    /// Raw応答がまだ記録されていません。
    case empty
    /// Raw応答が現在端末に保存されています。
    case available
    /// セッション概要を残して現在端末のRaw応答だけを除去しました。
    case removed
}

/// セッション転送の現在状態です。
enum ConnectionSessionCloudSyncState: String, Codable, Equatable, Sendable {
    /// 転送対象のRaw応答がまだありません。
    case notUploaded
    /// CloudKitへの転送を待っています。
    case pending
    /// CloudKitへ検証可能なManifestとともに保存しました。
    case uploaded
    /// 直近のCloudKit転送が失敗し再試行を待っています。
    case failed
}

/// Macがセッションを永続的に取り込んだことを示す受領証です。
struct ConnectionSessionMacImportReceipt: Codable, Equatable, Sendable {
    /// 取り込んだMacの安定したインストール識別子です。
    let deviceID: String
    /// ユーザーが判別できるMac表示名です。
    let deviceName: String
    /// Macで読み戻し検証まで完了した日時です。
    let importedAt: Date
    /// Macが検証した転送PayloadのSHA-256です。
    let manifestDigest: String

    /// 検証済みMac取込結果を受領証として生成します。
    ///
    /// 責務: 1台のMacによる完全取込結果をセッションManifestへ固定します。
    /// - Parameters:
    ///   - deviceID: Macの安定したインストール識別子。
    ///   - deviceName: ユーザー向けMac表示名。
    ///   - importedAt: 読み戻し検証まで完了した日時。
    ///   - manifestDigest: 検証した転送PayloadのSHA-256。
    init(deviceID: String, deviceName: String, importedAt: Date, manifestDigest: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.importedAt = importedAt
        self.manifestDigest = manifestDigest
    }
}

/// 接続履歴へ表示するRawログ件数と端末間保管状態です。
struct ConnectionSessionRawLogSummary: Codable, Equatable, Sendable {
    /// セッションへ記録されたRaw応答件数です。
    var recordCount: Int64
    /// セッションへ記録されたRaw応答Payload合計バイト数です。
    var byteCount: Int64
    /// 現在端末におけるRawログ保管状態です。
    var localState: ConnectionSessionLocalRawState
    /// CloudKit転送の現在状態です。
    var cloudState: ConnectionSessionCloudSyncState
    /// 転送Payloadを識別するSHA-256です。
    var manifestDigest: String?
    /// Macによる永続取込を確認できた場合の受領証です。
    var macImportReceipt: ConnectionSessionMacImportReceipt?

    /// Raw応答未記録の標準状態です。
    static let empty = ConnectionSessionRawLogSummary(
        recordCount: 0,
        byteCount: 0,
        localState: .empty,
        cloudState: .notUploaded,
        manifestDigest: nil,
        macImportReceipt: nil
    )

    /// セッションのRawログ件数と保管状態を生成します。
    ///
    /// 責務: Rawログの集計値と端末間保管証跡を1件の履歴表示値へまとめます。
    /// - Parameters:
    ///   - recordCount: Raw応答件数。
    ///   - byteCount: Raw応答Payload合計バイト数。
    ///   - localState: 現在端末の保管状態。
    ///   - cloudState: CloudKit転送状態。
    ///   - manifestDigest: 転送PayloadのSHA-256。
    ///   - macImportReceipt: Mac取込済みの場合の受領証。
    init(
        recordCount: Int64,
        byteCount: Int64,
        localState: ConnectionSessionLocalRawState,
        cloudState: ConnectionSessionCloudSyncState,
        manifestDigest: String?,
        macImportReceipt: ConnectionSessionMacImportReceipt?
    ) {
        self.recordCount = recordCount
        self.byteCount = byteCount
        self.localState = localState
        self.cloudState = cloudState
        self.manifestDigest = manifestDigest
        self.macImportReceipt = macImportReceipt
    }

    /// 現在のManifestと一致するMac受領証があるかを返します。
    var isDurablyImportedByMac: Bool {
        guard let manifestDigest, let receipt = macImportReceipt else { return false }
        return receipt.manifestDigest == manifestDigest
    }
}
