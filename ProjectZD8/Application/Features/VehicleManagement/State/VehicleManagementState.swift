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
    /// CloudKitまたはキャッシュから最後に読込を完了したかを示します。
    var hasLoadedVehicles = false
}
