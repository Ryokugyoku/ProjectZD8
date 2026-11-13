import Foundation

/// Raw Payloadを含めず端末間で常時共有する接続セッション概要です。
struct ConnectionSessionCloudMetadata: Codable, Equatable, Sendable {
    /// 端末固有の保管状態を除いた接続セッションです。
    let session: ConnectionSession
    /// CloudKit上のRaw Payloadを識別するSHA-256です。
    let manifestDigest: String

    /// 同期対象セッションとRaw Manifestを固定して生成します。
    ///
    /// 責務: 1件の接続セッションをRaw Payload非依存の同期概要へ変換します。
    /// - Parameters:
    ///   - session: 一覧表示へ共有する接続セッション。
    ///   - manifestDigest: CloudKit上のRaw Payloadを識別するSHA-256。
    init(session: ConnectionSession, manifestDigest: String) {
        self.session = session
        self.manifestDigest = manifestDigest
    }
}
