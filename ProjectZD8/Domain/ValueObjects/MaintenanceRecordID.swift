import Foundation

/// 車両別整備記録を端末間で安定して識別するIDです。
nonisolated struct MaintenanceRecordID: Hashable, Codable, Sendable {
    /// 永続化と同期に使用するUUIDです。
    let rawValue: UUID

    /// 新規または復元済みUUIDから整備記録IDを生成します。
    ///
    /// 責務: 1件のUUIDを整備記録専用の型へ包みます。
    /// - Parameter rawValue: 整備記録を一意に識別するUUID。
    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
