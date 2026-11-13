/// 動力区分と車両が保持するエネルギー源の整合規則です。
enum VehicleEnergySourcePolicy {
    /// 指定した動力区分で利用可能なエネルギー源を返します。
    ///
    /// 責務: 1件の動力区分を対応するエネルギー源候補へ変換します。
    /// - Parameter powertrain: 候補を求める動力区分。
    /// - Returns: 指定した動力区分で利用可能なエネルギー源。
    static func availableSources(for powertrain: VehiclePowertrainKind) -> [VehicleEnergySource] {
        switch powertrain {
        case .combustion:
            return [.gasolinePremium, .gasolineRegular, .diesel]
        case .hybrid, .plugInHybrid:
            return [.gasolinePremium, .gasolineRegular, .diesel, .electricity]
        case .batteryElectric:
            return [.electricity]
        case .fuelCell:
            return [.hydrogen]
        case .other:
            return [.other]
        }
    }

    /// 保持中のエネルギー源を動力区分で利用可能な範囲へ整えます。
    ///
    /// 責務: 利用可能な既存値を失わずに1件以上のエネルギー源を保証します。
    /// - Parameters:
    ///   - sources: 現在保持しているエネルギー源。
    ///   - powertrain: 適合先の動力区分。
    /// - Returns: 既存順を保った利用可能値、または動力区分の既定値1件。
    static func normalizedSources(
        _ sources: [VehicleEnergySource],
        for powertrain: VehiclePowertrainKind
    ) -> [VehicleEnergySource] {
        let available = availableSources(for: powertrain)
        let retained = sources.filter { available.contains($0) }
        guard retained.isEmpty else { return retained }
        if powertrain == .hybrid || powertrain == .plugInHybrid {
            return [.electricity]
        }
        return [available.first ?? .other]
    }

    /// 編集開始時に保存済みエネルギー源を非破壊で準備します。
    ///
    /// 責務: 保存済み値を変更せず、空の入力だけを動力区分の既定値で補完します。
    /// - Parameters:
    ///   - sources: 保存済みのエネルギー源。
    ///   - powertrain: 空の入力を補完する動力区分。
    /// - Returns: 保存済み値、または動力区分の既定値1件。
    static func sourcesForEditing(
        _ sources: [VehicleEnergySource],
        powertrain: VehiclePowertrainKind
    ) -> [VehicleEnergySource] {
        guard sources.isEmpty else { return sources }
        return normalizedSources([], for: powertrain)
    }
}
