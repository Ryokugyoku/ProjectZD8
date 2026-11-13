/// 動力区分で選べるエネルギー源1件の選択肢です。
nonisolated struct VehicleEnergySourceOption: Identifiable, Equatable, Sendable {
    /// エネルギー源です。
    let source: VehicleEnergySource
    /// 表示名のローカライズキーです。
    let nameKey: String
    /// 現在の入力で選択されているかどうかです。
    let isSelected: Bool

    /// `Identifiable` が使用する識別値です。
    var id: VehicleEnergySource { source }
}
