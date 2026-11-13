/// 車両が特定のPIDへ応答するかどうかの確認状態です。
nonisolated enum PIDSupport: String, Codable, CaseIterable, Sendable {
    case supported
    case unsupported
    /// 対応ビットマップで確認できていない。
    case unknown
}
