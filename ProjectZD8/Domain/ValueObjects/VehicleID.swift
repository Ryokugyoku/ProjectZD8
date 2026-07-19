import Foundation

/// 登録車両をVINなどの外部識別値から独立して識別します。
struct VehicleID: Hashable, Codable, Identifiable, Sendable {
    /// アプリが生成した安定した車両識別値です。
    let rawValue: UUID

    /// `Identifiable` が使用する安定識別値です。
    var id: UUID { rawValue }

    /// 指定値または新しいUUIDで車両識別値を生成します。
    ///
    /// 責務: 外部識別値へ依存しない車両識別値を1件生成します。
    /// - Parameter rawValue: 保持するUUID。
    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
