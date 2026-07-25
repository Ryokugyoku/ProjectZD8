/// CloudKitを介してセッションID単位で移動する未デコードログです。
struct ConnectionSessionTransferPackage: Codable, Equatable, Sendable {
    /// Rawログを所有する安定セッションIDです。
    let sessionID: ConnectionSessionID
    /// Rawログを所有するAppleアカウント識別子です。
    let accountIdentifier: String
    /// セッション順序を保持する全Raw応答です。
    let entries: [ConnectionSessionRawLogEntry]

    /// セッション識別情報と全Raw応答を1件の転送単位として生成します。
    ///
    /// 責務: 1件の安定セッションIDを端末間で再結合できるRaw Payloadへまとめます。
    /// - Parameters:
    ///   - sessionID: Rawログを所有する安定セッションID。
    ///   - accountIdentifier: Rawログを所有するAppleアカウント識別子。
    ///   - entries: セッション順に並ぶ未デコードRaw応答。
    init(
        sessionID: ConnectionSessionID,
        accountIdentifier: String,
        entries: [ConnectionSessionRawLogEntry]
    ) {
        self.sessionID = sessionID
        self.accountIdentifier = accountIdentifier
        self.entries = entries
    }

    /// 接続セッションから安定識別情報だけを取り出してRaw転送単位を生成します。
    ///
    /// 責務: 1件の接続セッションを表示メタデータ非包含のRaw Payloadへ変換します。
    /// - Parameters:
    ///   - session: 安定IDと所有アカウントを提供する接続セッション。
    ///   - entries: セッション順に並ぶ未デコードRaw応答。
    init(session: ConnectionSession, entries: [ConnectionSessionRawLogEntry]) {
        self.init(
            sessionID: session.id,
            accountIdentifier: session.accountIdentifier,
            entries: entries
        )
    }
}

/// CloudKitから検証済みで取得したセッションPayloadです。
struct VerifiedConnectionSessionTransfer: Equatable, Sendable {
    /// 復元するセッションPayloadです。
    let package: ConnectionSessionTransferPackage
    /// CloudKit AssetバイトのSHA-256です。
    let manifestDigest: String

    /// 検証済みPayloadとDigestを生成します。
    ///
    /// 責務: 1件の転送Payloadを検証済みManifest識別子へ結び付けます。
    /// - Parameters:
    ///   - package: 復元するセッションPayload。
    ///   - manifestDigest: AssetバイトのSHA-256。
    init(package: ConnectionSessionTransferPackage, manifestDigest: String) {
        self.package = package
        self.manifestDigest = manifestDigest
    }
}
