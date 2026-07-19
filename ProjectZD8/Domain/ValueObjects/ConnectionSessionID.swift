import Foundation

/// 走行接続セッションを外部識別値から独立して識別します。
struct ConnectionSessionID: Hashable, Codable, Identifiable, Sendable {
    /// アプリが生成した安定したセッション識別値です。
    let rawValue: UUID

    /// `Identifiable` が使用する安定識別値です。
    var id: UUID { rawValue }

    /// 指定値または新しいUUIDでセッション識別値を生成します。
    ///
    /// 責務: 1件の接続セッションへ安定したUUIDを割り当てます。
    /// - Parameter rawValue: 保持するUUID。
    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
