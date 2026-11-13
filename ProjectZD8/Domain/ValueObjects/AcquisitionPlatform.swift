/// セッションを取得した端末の種類です。
nonisolated enum AcquisitionPlatform: String, Codable, CaseIterable, Sendable {
    case iPhone
    case iPad
    case mac
}
