import Foundation

/// ユーザーが登録した1台の車両です。
nonisolated struct Vehicle: Identifiable, Equatable, Sendable {
    /// アプリが発行した車両IDです。ログ・整備記録・分析はこのIDにだけ紐づきます。
    let id: VehicleID
    /// 車両から読み取ったVINです。読み取れなかった場合は空文字です。
    let vin: String
    /// VINが無い車両を照合するための代替識別値です。
    let obdIdentifier: String?
    var name: String
    var manufacturer: String
    var engineModel: String
    var powertrain: VehiclePowertrainKind
    var energySources: [VehicleEnergySource]
    var tankCapacityLiters: Double?
    var modelYear: Int?
    var note: String
    /// 車両写真です。画像本体は `PhotoRepository` が保持します。
    var photoID: PhotoID?
    let createdAt: Date
    var modifiedAt: Date

    /// 車両を生成します。
    ///
    /// 責務: 1台の登録車両の属性をまとめます。
    init(
        id: VehicleID = VehicleID(),
        vin: String,
        obdIdentifier: String? = nil,
        name: String,
        manufacturer: String = "",
        engineModel: String = "",
        powertrain: VehiclePowertrainKind = .combustion,
        energySources: [VehicleEnergySource] = [.gasolineRegular],
        tankCapacityLiters: Double? = nil,
        modelYear: Int? = nil,
        note: String = "",
        photoID: PhotoID? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.vin = vin
        self.obdIdentifier = obdIdentifier
        self.name = name
        self.manufacturer = manufacturer
        self.engineModel = engineModel
        self.powertrain = powertrain
        self.energySources = energySources
        self.tankCapacityLiters = tankCapacityLiters
        self.modelYear = modelYear
        self.note = note
        self.photoID = photoID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// 車両を外部識別値で示す表示用文字列です。
    var displayIdentifier: String { vin.isEmpty ? (obdIdentifier ?? "") : vin }

    /// 車種専用PIDの選択に使う車種コードです。該当車種でなければ `nil` です。
    var modelCode: String? { ZD8VehicleModelPolicy().matches(self) ? ZD8VehicleModelPolicy.modelCode : nil }
}
