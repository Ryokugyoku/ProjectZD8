import Foundation

/// ローカルに保存する、軌跡の同期記録1行です。
nonisolated struct ConnectionSessionLocationTrackSyncRecord: Equatable, Sendable {
    /// 対象の接続セッション。
    let sessionID: ConnectionSessionID
    /// 同期記録の由来。
    let origin: ConnectionSessionLocationTrackSyncOrigin
    /// iCloud に保存された Asset バイト列の SHA-256(小文字16進)。
    let manifestDigest: String
    /// 同期した時点の水位。
    let watermark: ConnectionSessionLocationTrackWatermark
    /// 同期した時刻。
    let syncedAt: Date
}
