import Foundation

/// `RecordingSessionActivityAttributes` の入れ子の値型 `VehicleLabel` です。ActivityKit に依存せず、アプリ・Extension・macOS の単体テストで共有します。
extension RecordingSessionActivityAttributes {
    /// Live Activityの車両名欄の内容です。
    nonisolated enum VehicleLabel: Codable, Hashable, Sendable {
        /// 登録済み車両の名称です。
        case named(String)
        /// 未登録または名称不明の車両です。`unregisteredVehicleKey` の文言で描きます。
        case unregistered
    }
}
