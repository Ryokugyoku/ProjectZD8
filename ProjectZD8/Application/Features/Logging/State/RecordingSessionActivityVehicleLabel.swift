import Foundation

/// 記録中表示の車両名欄に出す内容です。
nonisolated enum RecordingSessionActivityVehicleLabel: Equatable, Codable, Sendable {
    /// 登録済み車両の名称です。
    case named(String)
    /// 未登録、または登録済みでも名称を確かめられない車両です。
    case unregistered

    /// 「未登録の車両」を表す文言のローカライズキーです。
    static let unregisteredKey = "live_activity.vehicle.unregistered"

    /// 車両名から表示内容を生成します。
    ///
    /// 責務: 空白だけの名称や名称なしを未登録表示へ変換します。
    /// - Parameter vehicleName: 登録済み車両の名称。未登録・不明なら `nil`。
    init(vehicleName: String?) {
        let trimmed = vehicleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self = trimmed.isEmpty ? .unregistered : .named(trimmed)
    }
}
