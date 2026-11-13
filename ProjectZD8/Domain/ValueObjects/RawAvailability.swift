/// セッションのRawサンプルがどこにあるかを表します。
nonisolated enum RawAvailability: String, Codable, CaseIterable, Sendable {
    /// この端末のデータベースにある。
    case local
    /// この端末からは解放済みで、iCloud上のアーカイブにだけある。
    case cloudOnly
}
