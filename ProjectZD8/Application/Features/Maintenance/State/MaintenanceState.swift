/// 整備画面が描画する状態です。
nonisolated struct MaintenanceState: Equatable, Sendable {
    /// 読み込み段階です。
    enum LoadPhase: Equatable, Sendable {
        case idle
        case loading
        case loaded
    }

    var loadPhase: LoadPhase = .idle
    /// 整備を記録できる車両です。
    var vehicles: [MaintenanceVehicleOption] = []
    /// 一覧を表示している車両です。車両が無ければ `nil` です。
    var selectedVehicleID: VehicleID?
    /// 選択車両の整備記録を実施日の新しい順に並べた行です。
    var rows: [MaintenanceListRow] = []
    /// 区分での絞り込みです。`nil` なら全区分です。
    var kindFilter: MaintenanceKind?
    /// 開いている編集画面です。閉じていれば `nil` です。
    var editor: MaintenanceEditorState?
    /// 削除の確認待ちの内容です。
    var pendingDeletion: MaintenanceDeletionPrompt?
    /// 直近の失敗です。`failureDismissed` で消えます。
    var failure: MaintenanceFailure?

    /// 区分の絞り込み後に表示する行です。
    var visibleRows: [MaintenanceListRow] {
        guard let kindFilter else { return rows }
        return rows.filter { $0.kind == kindFilter }
    }
    /// 軽整備の件数です。
    var lightCount: Int { rows.filter { $0.kind == .light }.count }
    /// 重整備の件数です。
    var heavyCount: Int { rows.filter { $0.kind == .heavy }.count }
}
