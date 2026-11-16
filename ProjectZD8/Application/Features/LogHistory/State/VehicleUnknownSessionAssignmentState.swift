/// 車両不明ログを登録済みの車両へ紐付ける画面の状態です。
nonisolated struct VehicleUnknownSessionAssignmentState: Equatable, Sendable {
    /// 画面を表示中かどうかです。
    var isPresented = false
    /// 紐付けの候補にする車両不明ログです(新しい順)。
    var sessions: [ConnectionSession] = []
    /// 選んだログのIDです。
    var selectedSessionIDs: Set<ConnectionSessionID> = []
    /// 選んだ車両のIDです。
    var selectedVehicleID: VehicleID?
    /// 直近の紐付けが失敗した時の文言キーです。成功・選択の変更で `nil` へ戻ります。
    var failureKey: String?

    /// 紐付けを実行できるかどうかを返します。
    ///
    /// 責務: ログを1件以上選び、選んだ車両が候補の車両に含まれることを判定します。
    /// - Parameter vehicles: 候補の登録済み車両。
    /// - Returns: 実行できるなら `true`。
    func canAssign(among vehicles: [VehicleProfile]) -> Bool {
        guard !selectedSessionIDs.isEmpty, let selectedVehicleID else { return false }
        return vehicles.contains { $0.id == selectedVehicleID }
    }

    /// 指定したログが選ばれているかどうかを返します。
    ///
    /// 責務: 選択集合に含まれるかを判定します。
    /// - Parameter id: ログのID。
    /// - Returns: 選ばれていれば `true`。
    func isSelected(_ id: ConnectionSessionID) -> Bool {
        selectedSessionIDs.contains(id)
    }

    /// 候補の車両が無い時に表示する案内のローカライズキーです。
    ///
    /// 責務: 候補が空なら車両登録の案内キーを、あれば `nil` を返します。
    /// - Parameter vehicles: 候補の登録済み車両。
    /// - Returns: 案内キー、または `nil`。
    func noVehicleMessageKey(among vehicles: [VehicleProfile]) -> String? {
        vehicles.isEmpty ? "vehicle_unknown.assignment.no_vehicles" : nil
    }
}
