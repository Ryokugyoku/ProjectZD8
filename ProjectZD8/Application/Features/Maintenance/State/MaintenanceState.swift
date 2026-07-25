import Foundation

/// 整備編集画面へ表示する未保存入力です。
struct MaintenanceEditorDraft: Equatable {
    /// 編集元記録IDです。
    let recordID: MaintenanceRecordID?
    /// 必ず関連付ける登録車両IDです。
    var vehicleID: VehicleID
    /// 軽整備または重整備の区分です。
    var kind: MaintenanceKind
    /// 作業表題です。
    var title: String
    /// 作業実施日時です。
    var performedAt: Date
    /// 走行距離入力です。
    var odometerKilometers: Double?
    /// 作業全体の詳細記録です。
    var notes: String
    /// 部品ごとの作業入力です。
    var workItems: [MaintenanceWorkItem]
    /// 作業写真です。
    var photos: [MaintenancePhoto]
    /// 分解・締結証跡です。
    var fastenerGroups: [MaintenanceFastenerGroup]
    /// 編集元の作成日時です。
    let createdAt: Date

    /// 新規整備入力を車両と区分から生成します。
    ///
    /// 責務: 1台分の未保存整備入力を安全な初期値で生成します。
    /// - Parameters:
    ///   - vehicleID: 整備対象の登録車両ID。
    ///   - kind: 軽整備または重整備。
    ///   - now: 初期の実施日時と作成日時。
    init(vehicleID: VehicleID, kind: MaintenanceKind, now: Date = Date()) {
        recordID = nil
        self.vehicleID = vehicleID
        self.kind = kind
        title = ""
        performedAt = now
        odometerKilometers = nil
        notes = ""
        workItems = []
        photos = []
        fastenerGroups = []
        createdAt = now
    }

    /// 保存済み記録から編集入力を生成します。
    ///
    /// 責務: 1件のDomain整備記録を変更可能な画面入力へ写像します。
    /// - Parameter record: 編集する保存済み整備記録。
    init(record: MaintenanceRecord) {
        recordID = record.id
        vehicleID = record.vehicleID
        kind = record.kind
        title = record.title
        performedAt = record.performedAt
        odometerKilometers = record.odometerKilometers
        notes = record.notes
        workItems = record.workItems
        photos = record.photos
        fastenerGroups = record.fastenerGroups
        createdAt = record.createdAt
    }
}

/// 整備画面が描画する同期済み一覧と編集状態です。
struct MaintenanceState: Equatable {
    /// 整備機能の現在段階です。
    enum Phase: Equatable {
        /// 操作待ちです。
        case idle
        /// ローカルとCloudKitを同期しています。
        case syncing
        /// 新規または既存記録を編集中です。
        case editing
        /// 編集内容を保存しています。
        case saving
        /// 読込、保存、同期のいずれかに失敗しました。
        case failed
    }

    /// 現在のワークフロー段階です。
    var phase: Phase = .idle
    /// 整備対象として選べる登録車両です。
    var vehicles: [VehicleProfile] = []
    /// 一覧表示中の登録車両IDです。
    var selectedVehicleID: VehicleID?
    /// 削除墓石を除く整備記録です。
    var records: [MaintenanceRecord] = []
    /// 軽整備または重整備で絞り込む選択です。
    var kindFilter: MaintenanceKind?
    /// 表示中の未保存編集入力です。
    var draft: MaintenanceEditorDraft?
    /// 直近の失敗を説明するローカライズキーです。
    var failureKey: String?
    /// CloudKitとの同期を最後に完了した日時です。
    var lastSynchronizedAt: Date?

    /// 選択車両と区分に一致する表示用記録です。
    var visibleRecords: [MaintenanceRecord] {
        records.filter { record in
            (selectedVehicleID == nil || record.vehicleID == selectedVehicleID)
                && (kindFilter == nil || record.kind == kindFilter)
        }
    }
}
