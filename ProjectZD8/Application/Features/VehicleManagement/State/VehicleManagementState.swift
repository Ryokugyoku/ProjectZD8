import Foundation

/// 車両識別、登録、一覧編集の現在状態です。
struct VehicleManagementState: Equatable {
    /// 車両管理ワークフローの現在段階です。
    enum Phase: Equatable {
        /// アカウント確定前または操作待ちです。
        case idle
        /// 同期先から一覧を読み込んでいます。
        case loading
        /// OBDから識別情報を取得しています。
        case identifying
        /// 未登録VINと全取得情報の確認を待っています。
        case confirmingIdentification
        /// 新規車両の入力を待っています。
        case registering
        /// 既存車両の編集を待っています。
        case editing
        /// 登録済み車両へ接続を引き渡せる状態です。
        case readyToConnect
        /// OBD識別が未提供または処理に失敗しました。
        case failed
    }

    /// 現在のワークフロー段階です。
    var phase: Phase = .idle
    /// アカウントに属する登録車両です。
    var vehicles: [VehicleProfile] = []
    /// 確認中のOBD識別観測です。
    var pendingIdentification: VehicleIdentificationSnapshot?
    /// 編集中の車両プロフィールです。
    var editingVehicle: VehicleProfile?
    /// 接続対象として確定した登録車両です。
    var connectionVehicle: VehicleProfile?
    /// 現在の識別または再試行で使用するOBD物理終端です。
    var connectionEndpoint: OBDConnectionEndpoint?
    /// 直近の失敗をユーザーへ説明するローカライズキーです。
    var failureKey: String?
    /// 直近のOBD識別失敗で完了できなかった型付き段階です。
    var identificationFailureStage: VehicleIdentificationError.Stage?
    /// CloudKitまたはキャッシュから最後に読込を完了したかを示します。
    var hasLoadedVehicles = false
    /// PID収集設定を表示している車両IDです。
    var pidSettingsVehicleID: VehicleID?
    /// PID収集設定へ表示する対応PID一覧です。
    var pidSelectionItems: [VehiclePIDSelectionItem] = []
    /// 登録車両ごとの接続・ログ集計です。
    var activityByVehicleID: [VehicleID: VehicleActivitySummary] = [:]
    /// 対応登録済みの車種専用PID型式です。
    var specialPIDModelCodeByVehicleID: [VehicleID: String] = [:]
}

/// Garageへ表示する1台分の接続・ログ集計です。
struct VehicleActivitySummary: Equatable, Sendable {
    /// 記録済み接続セッション件数です。
    let sessionCount: Int
    /// 最後にログを記録した日時です。
    let lastLoggedAt: Date?
    /// 全セッションの記録済み走行時間です。
    let totalRecordedDuration: TimeInterval
    /// 正常終了しなかったセッション件数です。
    let interruptedCount: Int
    /// 現在進行中の接続セッションがあるかを示します。
    let isConnected: Bool
    /// Garageへ表示できる直近セッションの累積走行距離です。
    let latestOdometerKilometers: Double?
    /// 累積走行距離を車種専用PIDから取得した場合の型式です。
    let odometerModelCode: String?

    /// ログ未記録の初期集計を生成します。
    ///
    /// 責務: Garage表示用アクティビティを履歴なしの安全なゼロ値で初期化します。
    /// - Parameters:
    ///   - sessionCount: 記録済み接続セッション件数。
    ///   - lastLoggedAt: 最後にログを記録した日時。
    ///   - totalRecordedDuration: 全セッションの記録済み走行時間。
    ///   - interruptedCount: 正常終了しなかったセッション件数。
    ///   - isConnected: 現在進行中の接続セッションがあるか。
    ///   - latestOdometerKilometers: Garageへ表示する最新の累積走行距離。
    ///   - odometerModelCode: 累積走行距離を車種専用PIDから取得した場合の型式。
    init(
        sessionCount: Int = 0,
        lastLoggedAt: Date? = nil,
        totalRecordedDuration: TimeInterval = 0,
        interruptedCount: Int = 0,
        isConnected: Bool = false,
        latestOdometerKilometers: Double? = nil,
        odometerModelCode: String? = nil
    ) {
        self.sessionCount = sessionCount
        self.lastLoggedAt = lastLoggedAt
        self.totalRecordedDuration = totalRecordedDuration
        self.interruptedCount = interruptedCount
        self.isConnected = isConnected
        self.latestOdometerKilometers = latestOdometerKilometers
        self.odometerModelCode = odometerModelCode
    }
}

/// 車両設定画面へ表示する1件の対応PID収集選択です。
struct VehiclePIDSelectionItem: Equatable, Identifiable {
    /// Service/PID識別子です。
    let id: OBDPIDRequest
    /// PIDテーブルに定義がある場合の名称キーです。
    let nameKey: String?
    /// 継続収集の有効状態です。
    var isEnabled: Bool
    /// 車種専用PIDの場合に表示する型式です。
    let vehicleModelCode: String?
}
