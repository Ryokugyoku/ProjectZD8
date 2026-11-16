import Foundation

/// `RecordingSessionActivityAttributes` の入れ子の値型 `StatusTone` です。ActivityKit に依存せず、アプリ・Extension・macOS の単体テストで共有します。
extension RecordingSessionActivityAttributes {
    /// 状態欄の強調です。
    nonisolated enum StatusTone: Codable, Hashable, Sendable {
        /// 通常(シアン)です。
        case normal
        /// 警告(オレンジ)です。
        case warning
    }
}
