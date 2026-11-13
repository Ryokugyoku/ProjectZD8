/// 変更通知の対象にできる永続化データの領域です。
nonisolated enum StoreArea: String, CaseIterable, Sendable {
    case vehicles
    case pidSettings
    case maintenance
    case photos
    case sessions
}
