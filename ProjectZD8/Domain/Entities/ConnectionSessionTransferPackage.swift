/// CloudKitを介して端末間を移動する1セッション分の未デコードログです。
struct ConnectionSessionTransferPackage: Codable, Equatable, Sendable {
    /// 接続履歴と車両関連付けを保持するセッションです。
    let session: ConnectionSession
    /// セッション順序を保持する全Raw応答です。
    let entries: [ConnectionSessionRawLogEntry]

    /// セッションと全Raw応答を1件の転送単位として生成します。
    ///
    /// 責務: 1件の終了済みセッションを端末間で完全復元できるPayloadへまとめます。
    /// - Parameters:
    ///   - session: 車両関連付けを含む接続セッション。
    ///   - entries: セッション順に並ぶ未デコードRaw応答。
    init(session: ConnectionSession, entries: [ConnectionSessionRawLogEntry]) {
        self.session = session
        self.entries = entries
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
