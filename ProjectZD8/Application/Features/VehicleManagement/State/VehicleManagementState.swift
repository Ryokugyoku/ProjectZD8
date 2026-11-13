/// 車両管理画面が描画する状態です。
nonisolated struct VehicleManagementState: Equatable, Sendable {
    /// 一覧の読み込み段階です。
    enum LoadPhase: Equatable, Sendable {
        /// 読み込み前です。
        case idle
        /// 読み込み中です。
        case loading
        /// 読み込み済みです。
        case loaded
    }

    var loadPhase: LoadPhase = .idle
    /// 登録車両を名称順に並べた一覧です。
    var vehicles: [VehicleListItem] = []
    /// 開いている編集画面です。閉じていれば `nil` です。
    var editor: VehicleEditorState?
    /// 削除の確認待ちの内容です。
    var pendingDeletion: VehicleDeletionPrompt?
    /// 開いているPID収集設定画面です。閉じていれば `nil` です。
    var pidSettings: VehiclePIDSettingsState?
    /// 直近の失敗です。`failureDismissed` で消えます。
    var failure: VehicleManagementFailure?
    /// 記録中のセッションを持つ車両が1台以上あるかどうかです。
    var hasRecordingVehicle: Bool { vehicles.contains { $0.activity.isRecording } }
}
