/// digest の照合を済ませた、iCloud から取得した軌跡です。
nonisolated struct VerifiedConnectionSessionLocationTrack: Equatable, Sendable {
    /// 復号した軌跡。
    let track: ConnectionSessionLocationTrack
    /// 照合済みの Asset バイト列の SHA-256(小文字16進)。
    let manifestDigest: String
}
