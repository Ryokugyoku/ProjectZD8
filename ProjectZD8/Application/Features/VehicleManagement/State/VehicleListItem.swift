import Foundation

/// 車両一覧の1行分です。
nonisolated struct VehicleListItem: Identifiable, Equatable, Sendable {
    /// 登録車両です。
    let vehicle: Vehicle
    /// 記録活動の集計です。
    let activity: VehicleActivitySummary
    /// 車両写真の画像データです。写真なし、または読み込めない場合は `nil` です。
    let photoData: Data?

    /// `Identifiable` が使用する識別値です。
    var id: VehicleID { vehicle.id }
    /// 動力区分の表示名キーです。
    var powertrainNameKey: String { "garage.powertrain.\(vehicle.powertrain.rawValue)" }
    /// エネルギー源の表示名キーです。
    var energySourceNameKeys: [String] { vehicle.energySources.map { "garage.energy.\($0.rawValue)" } }
}
