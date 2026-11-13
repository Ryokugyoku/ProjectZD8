import Foundation

/// 車両編集画面の未保存入力です。
nonisolated struct VehicleEditDraft: Equatable, Sendable {
    /// 編集対象の車両IDです。
    let vehicleID: VehicleID
    /// 車両から読み取ったVINです(編集不可の表示用)。
    let vin: String
    /// VINが無い車両の代替識別値です(編集不可の表示用)。
    let obdIdentifier: String?
    var name: String
    var manufacturer: String
    var engineModel: String
    var powertrain: VehiclePowertrainKind
    var energySources: [VehicleEnergySource]
    /// 燃料タンク容量(L)です。未入力は `nil` です。
    var tankCapacityLiters: Double?
    var modelYear: Int?
    var note: String
    /// 現在選択中の写真です。写真なしは `nil` です。
    var photoID: PhotoID?

    /// 保存済み車両から編集入力を生成します。
    ///
    /// 責務: 保存済みの値を失わずに編集入力へ写します。
    init(vehicle: Vehicle) {
        vehicleID = vehicle.id
        vin = vehicle.vin
        obdIdentifier = vehicle.obdIdentifier
        name = vehicle.name
        manufacturer = vehicle.manufacturer
        engineModel = vehicle.engineModel
        powertrain = vehicle.powertrain
        energySources = VehicleEnergySourcePolicy.sourcesForEditing(vehicle.energySources, powertrain: vehicle.powertrain)
        tankCapacityLiters = vehicle.tankCapacityLiters
        modelYear = vehicle.modelYear
        note = vehicle.note
        photoID = vehicle.photoID
    }

    /// 動力区分で選べるエネルギー源と、その選択状態です。
    var energySourceOptions: [VehicleEnergySourceOption] {
        VehicleEnergySourcePolicy.availableSources(for: powertrain).map {
            VehicleEnergySourceOption(source: $0, nameKey: "garage.energy.\($0.rawValue)", isSelected: energySources.contains($0))
        }
    }

    /// エネルギー源の選択を切り替えます。
    ///
    /// 責務: 1件のエネルギー源を選択集合へ加える、または外します。
    mutating func toggleEnergySource(_ source: VehicleEnergySource) {
        if let index = energySources.firstIndex(of: source) {
            energySources.remove(at: index)
        } else {
            energySources.append(source)
        }
    }

    /// 入力を検証します。
    ///
    /// 責務: 保存できない入力を問題の一覧として返します。
    /// - Parameter currentYear: 年式の上限判定に使う現在の西暦。
    /// - Returns: 問題の一覧。空なら保存できます。
    func issues(currentYear: Int) -> [VehicleEditIssue] {
        var result: [VehicleEditIssue] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.nameRequired) }
        if let tank = tankCapacityLiters, !(tank > 0 && tank.isFinite) { result.append(.tankCapacityInvalid) }
        if let year = modelYear, !(1900...(currentYear + 1)).contains(year) { result.append(.modelYearInvalid) }
        return result
    }

    /// 入力を車両へ反映します。
    ///
    /// 責務: 検証済みの入力から保存用の車両を作ります。エネルギー源は動力区分に合わせて整えます。
    /// - Parameters:
    ///   - vehicle: 反映先の保存済み車両。
    ///   - modifiedAt: 更新日時。
    func applied(to vehicle: Vehicle, modifiedAt: Date) -> Vehicle {
        var updated = vehicle
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.manufacturer = manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.engineModel = engineModel.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.powertrain = powertrain
        updated.energySources = VehicleEnergySourcePolicy.normalizedSources(energySources, for: powertrain)
        updated.tankCapacityLiters = tankCapacityLiters
        updated.modelYear = modelYear
        updated.note = note
        updated.photoID = photoID
        updated.modifiedAt = modifiedAt
        return updated
    }
}
