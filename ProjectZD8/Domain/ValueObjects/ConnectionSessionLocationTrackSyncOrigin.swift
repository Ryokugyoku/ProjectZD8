/// 同期記録の由来です。rawValue は DB の CHECK 制約に固定されます。
nonisolated enum ConnectionSessionLocationTrackSyncOrigin: String, Equatable, Sendable, CaseIterable {
    /// この端末で記録して送った。
    case uploaded
    /// iCloud から復元した(この端末からは送らない)。
    case restored
}
