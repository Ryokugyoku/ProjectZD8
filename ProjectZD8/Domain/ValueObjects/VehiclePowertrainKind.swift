/// 車両の動力構成を燃料種別から独立して分類します。
nonisolated enum VehiclePowertrainKind: String, CaseIterable, Codable, Sendable {
    /// 内燃機関のみで走行する構成です。
    case combustion
    /// 外部充電を行わないハイブリッド構成です。
    case hybrid
    /// 外部充電可能なハイブリッド構成です。
    case plugInHybrid
    /// 駆動用電池のみを主動力とする構成です。
    case batteryElectric
    /// 燃料電池を主電源とする構成です。
    case fuelCell
    /// 既知の分類へ確定できない構成です。
    case other
}
