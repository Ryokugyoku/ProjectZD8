import Foundation

/// 走行セッションを外部識別値から独立して識別します。
nonisolated struct SessionID: Hashable, Codable, Identifiable, Sendable {
    /// アプリが生成した安定した識別値です。
    let rawValue: UUID

    /// `Identifiable` が使用する安定識別値です。
    var id: UUID { rawValue }

    /// 指定値または新しいUUIDで識別値を生成します。
    ///
    /// 責務: 走行セッションの識別値を1件生成します。
    /// - Parameter rawValue: 保持するUUID。
    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
