import Foundation

/// 車両ごとの整備区分です。
nonisolated enum MaintenanceKind: String, Codable, CaseIterable, Sendable {
    /// 消耗品交換など日常的な軽整備です。
    case light
    /// 専門的な分解、修理、オーバーホールを含む重整備です。
    case heavy
}

/// 軽整備の消耗品と重整備の主要部品を共通選択肢として表します。
nonisolated enum MaintenanceComponent: String, Codable, CaseIterable, Sendable {
    /// エンジンオイルです。
    case engineOil
    /// オイルフィルターです。
    case oilFilter
    /// エアフィルターです。
    case airFilter
    /// タイヤです。
    case tires
    /// ブレーキパッドです。
    case brakePads
    /// 補機バッテリーです。
    case auxiliaryBattery
    /// ワイパーです。
    case wipers
    /// 冷却液です。
    case coolant
    /// トランスミッションフルードです。
    case transmissionFluid
    /// デファレンシャルオイルです。
    case differentialFluid
    /// スパークプラグです。
    case sparkPlugs
    /// ベルト類です。
    case belts
    /// 灯火類です。
    case bulbs
    /// エンジン本体です。
    case engineAssembly
    /// トランスミッション本体です。
    case transmission
    /// 駆動系です。
    case driveline
    /// サスペンションです。
    case suspension
    /// ステアリングです。
    case steering
    /// ブレーキシステムです。
    case brakingSystem
    /// 排気系です。
    case exhaust
    /// 燃料系です。
    case fuelSystem
    /// 冷却系です。
    case coolingSystem
    /// 電装系です。
    case electrical
    /// 空調系です。
    case airConditioning
    /// 安全装置です。
    case safetySystem
    /// 高電圧バッテリーです。
    case highVoltageBattery
    /// 駆動モーターまたは発電機です。
    case tractionMotor
    /// ボディまたはフレームです。
    case bodyFrame
    /// 一覧外の部品です。
    case other
}

/// 整備対象へ実施した作業種別です。
nonisolated enum MaintenanceOperation: String, Codable, CaseIterable, Sendable {
    /// 点検です。
    case inspection
    /// 交換です。
    case replacement
    /// 修理です。
    case repair
    /// 調整です。
    case adjustment
    /// オーバーホールです。
    case overhaul
    /// 清掃です。
    case cleaning
    /// 診断です。
    case diagnosis
    /// 加工または製作です。
    case fabrication
}

/// 1件の整備で対象にした部品と作業内容です。
nonisolated struct MaintenanceWorkItem: Identifiable, Equatable, Codable, Sendable {
    /// 作業項目の安定IDです。
    let id: UUID
    /// 選択した消耗品または主要部品です。
    var component: MaintenanceComponent
    /// 実施した作業種別です。
    var operation: MaintenanceOperation
    /// 使用または交換した部品名です。
    var partName: String
    /// こだわりを残す製品名です。
    var productName: String
    /// 製品メーカーです。
    var manufacturer: String
    /// 粘度、認証、型番などの仕様です。
    var specification: String
    /// 使用数量です。
    var quantity: Double?
    /// 数量の単位です。
    var unit: String
    /// 項目固有の詳しい作業記録です。
    var notes: String

    /// 選択部品と作業種別から作業項目を生成します。
    ///
    /// 責務: 1件の整備対象に製品情報と作業メモを関連付けます。
    init(
        id: UUID = UUID(),
        component: MaintenanceComponent,
        operation: MaintenanceOperation,
        partName: String = "",
        productName: String = "",
        manufacturer: String = "",
        specification: String = "",
        quantity: Double? = nil,
        unit: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.component = component
        self.operation = operation
        self.partName = partName
        self.productName = productName
        self.manufacturer = manufacturer
        self.specification = specification
        self.quantity = quantity
        self.unit = unit
        self.notes = notes
    }
}

/// 整備記録に添付する写真エビデンスです。
nonisolated struct MaintenancePhoto: Identifiable, Equatable, Codable, Sendable {
    /// 写真を同期先でも識別する安定IDです。
    let id: UUID
    /// 写真の画像データです。
    let data: Data
    /// 写真が示す内容の説明です。
    var caption: String
    /// 写真を記録へ追加した日時です。
    let capturedAt: Date

    /// 画像データを説明付きの整備エビデンスへ変換します。
    ///
    /// 責務: 1枚の画像を追跡可能な整備写真として生成します。
    init(id: UUID = UUID(), data: Data, caption: String = "", capturedAt: Date = Date()) {
        self.id = id
        self.data = data
        self.caption = caption
        self.capturedAt = capturedAt
    }
}

/// 1本の締結部品に対する組立時エビデンスです。
nonisolated struct FastenerInstallationEvidence: Identifiable, Equatable, Codable, Sendable {
    /// 締結証跡の安定IDです。
    let id: UUID
    /// 図面、写真、現物と照合できる取付位置です。
    var position: String
    /// 実際に締め付けたトルク値です。
    var torqueNewtonMeters: Double?
    /// 使用した工具またはトルクレンチです。
    var tool: String
    /// 締結を実施した担当者です。
    var tightenedBy: String
    /// 締結を実施した日時です。
    var tightenedAt: Date?
    /// 締結状態を示す写真IDです。
    var photoIDs: [UUID]
    /// 個別締結に関する補足です。
    var notes: String

    /// 位置を起点に個別締結証跡を生成します。
    ///
    /// 責務: 1本の締結位置へトルクと実施情報を関連付けます。
    init(
        id: UUID = UUID(),
        position: String,
        torqueNewtonMeters: Double? = nil,
        tool: String = "",
        tightenedBy: String = "",
        tightenedAt: Date? = nil,
        photoIDs: [UUID] = [],
        notes: String = ""
    ) {
        self.id = id
        self.position = position
        self.torqueNewtonMeters = torqueNewtonMeters
        self.tool = tool
        self.tightenedBy = tightenedBy
        self.tightenedAt = tightenedAt
        self.photoIDs = photoIDs
        self.notes = notes
    }
}

/// 分解時のネジ本数と組立時の個別締結証跡をまとめます。
nonisolated struct MaintenanceFastenerGroup: Identifiable, Equatable, Codable, Sendable {
    /// 締結グループの安定IDです。
    let id: UUID
    /// エンジン部位やカバー名などのグループ名称です。
    var name: String
    /// 車両上の分解位置です。
    var location: String
    /// 分解前に想定した本数です。
    var expectedCount: Int?
    /// 分解時に実際に回収した本数です。
    var removedCount: Int
    /// 分解順序、保管場所、異常などの記録です。
    var removalNotes: String
    /// 分解状態を示す写真IDです。
    var removalPhotoIDs: [UUID]
    /// 組立時に1本ずつ残す締結証跡です。
    var installations: [FastenerInstallationEvidence]

    /// 任意のエンジン構成に対応する可変締結グループを生成します。
    ///
    /// 責務: 1か所の分解本数と個別組立証跡を追跡可能にします。
    init(
        id: UUID = UUID(),
        name: String,
        location: String = "",
        expectedCount: Int? = nil,
        removedCount: Int = 0,
        removalNotes: String = "",
        removalPhotoIDs: [UUID] = [],
        installations: [FastenerInstallationEvidence] = []
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.expectedCount = expectedCount
        self.removedCount = removedCount
        self.removalNotes = removalNotes
        self.removalPhotoIDs = removalPhotoIDs
        self.installations = installations
    }
}

/// 1台の登録車両へ必ず関連付く軽整備または重整備の記録です。
nonisolated struct MaintenanceRecord: Identifiable, Equatable, Codable, Sendable {
    /// 整備記録の安定IDです。
    let id: MaintenanceRecordID
    /// 記録対象となる登録車両の安定IDです。
    let vehicleID: VehicleID
    /// 軽整備または重整備の区分です。
    let kind: MaintenanceKind
    /// 一覧で作業を識別する表題です。
    var title: String
    /// 整備を実施した日時です。
    var performedAt: Date
    /// 整備時点の走行距離です。
    var odometerKilometers: Double?
    /// 作業全体の詳しい記録です。
    var notes: String
    /// 対象部品と実施作業です。
    var workItems: [MaintenanceWorkItem]
    /// 作業前後や部品状態を残す写真です。
    var photos: [MaintenancePhoto]
    /// オーバーホール時の分解・締結追跡です。
    var fastenerGroups: [MaintenanceFastenerGroup]
    /// 記録を作成した日時です。
    let createdAt: Date
    /// 最後に記録内容を更新した日時です。
    var updatedAt: Date
    /// 全端末へ削除を伝播する墓石日時です。
    var deletedAt: Date?

    /// 車両IDを必須として整備記録を生成します。
    ///
    /// 責務: 1台の登録車両へ整備内容と証跡を関連付けます。
    init(
        id: MaintenanceRecordID = MaintenanceRecordID(),
        vehicleID: VehicleID,
        kind: MaintenanceKind,
        title: String,
        performedAt: Date = Date(),
        odometerKilometers: Double? = nil,
        notes: String = "",
        workItems: [MaintenanceWorkItem] = [],
        photos: [MaintenancePhoto] = [],
        fastenerGroups: [MaintenanceFastenerGroup] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.kind = kind
        self.title = title
        self.performedAt = performedAt
        self.odometerKilometers = odometerKilometers
        self.notes = notes
        self.workItems = workItems
        self.photos = photos
        self.fastenerGroups = fastenerGroups
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
