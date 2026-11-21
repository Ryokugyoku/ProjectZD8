/// Asset を取得せずに読める、iCloud 上の軌跡レコードの概要です。
nonisolated struct ConnectionSessionLocationTrackRemoteManifest: Equatable, Sendable {
    /// 対象の接続セッション。
    let sessionID: ConnectionSessionID
    /// Asset バイト列の SHA-256(小文字16進)。
    let manifestDigest: String
    /// サンプルの件数。
    let sampleCount: Int
    /// 事象の件数。
    let eventCount: Int
}
