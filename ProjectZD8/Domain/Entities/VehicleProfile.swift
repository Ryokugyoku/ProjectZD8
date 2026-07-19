import Foundation

/// 登録済み車両の識別情報とユーザー編集可能なプロフィールです。
struct VehicleProfile: Identifiable, Equatable, Codable, Sendable {
    /// アプリ内で車両を識別する安定IDです。
    let id: VehicleID
    /// OBD観測で確認されたVINです。
    let vin: String
    /// VINと確認できないOBD由来の識別子です。
    let obdIdentifier: String?
    /// ユーザーが編集できる車両名称です。
    var name: String
    /// 確認済みまたはユーザー入力のメーカー名です。
    var manufacturer: String
    /// 確認済みまたはユーザー入力のエンジン型式です。
    var engineModel: String
    /// 車両の動力構成です。
    var powertrain: VehiclePowertrainKind
    /// 車両が使用する1件以上のエネルギー源です。
    var energySources: [VehicleEnergySource]
    /// 液体または気体燃料タンクの容量です。
    var tankCapacityLiters: Double?
    /// ユーザーが確認したモデル年です。
    var modelYear: Int?
    /// ユーザーの任意メモです。
    var note: String
    /// カードへ表示する同期対象画像データです。
    var photoData: Data?
    /// この車両が既定の接続対象かどうかです。
    var isDefault: Bool
    /// 最後にプロフィールを更新した日時です。
    var updatedAt: Date

    /// VINとOBD由来識別子を混同せず表示用の代表値を返します。
    var displayIdentifier: String {
        vin.isEmpty ? (obdIdentifier ?? "") : vin
    }

    /// 登録に必要な車両プロフィールを生成します。
    ///
    /// 責務: 1台分の識別値とユーザー編集値を登録可能なプロフィールへまとめます。
    init(
        id: VehicleID = VehicleID(),
        vin: String,
        obdIdentifier: String? = nil,
        name: String,
        manufacturer: String = "",
        engineModel: String = "",
        powertrain: VehiclePowertrainKind = .combustion,
        energySources: [VehicleEnergySource] = [.gasoline],
        tankCapacityLiters: Double? = nil,
        modelYear: Int? = nil,
        note: String = "",
        photoData: Data? = nil,
        isDefault: Bool = false,
        updatedAt: Date = Date()
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
        self.photoData = photoData
        self.isDefault = isDefault
        self.updatedAt = updatedAt
    }
}
