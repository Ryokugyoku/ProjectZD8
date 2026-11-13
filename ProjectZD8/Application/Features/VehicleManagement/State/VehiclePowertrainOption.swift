/// 動力区分の選択肢です。
nonisolated struct VehiclePowertrainOption: Identifiable, Equatable, Sendable {
    /// 動力区分です。
    let kind: VehiclePowertrainKind
    /// 表示名のローカライズキーです。
    let nameKey: String

    /// `Identifiable` が使用する識別値です。
    var id: VehiclePowertrainKind { kind }

    /// 全動力区分を並べた選択肢です。
    static let all: [VehiclePowertrainOption] = VehiclePowertrainKind.allCases.map {
        VehiclePowertrainOption(kind: $0, nameKey: "garage.powertrain.\($0.rawValue)")
    }
}
