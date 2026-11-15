/// 登録済み車両のVINと一致する観測VINを持つ未紐付け接続セッションへ、その車両を設定します。
struct AssignVehicleToObservedVINConnectionSessionsUseCase {
    /// 観測VIN付きセッションの更新境界です。
    private let repository: any ObservedVINConnectionSessionRepository
    /// 履歴の再読込が必要になったことを通知する処理です。
    private let historyDidChange: @MainActor () -> Void

    /// 更新境界と履歴更新の通知先を固定します。
    ///
    /// 責務: 観測VINによる車両紐付けに使う永続化境界と通知先を保持します。
    /// - Parameters:
    ///   - repository: 観測VIN付きセッションの更新境界。
    ///   - historyDidChange: 1件以上紐付けた後に履歴再読込を通知する処理。
    init(
        repository: any ObservedVINConnectionSessionRepository,
        historyDidChange: @escaping @MainActor () -> Void = {}
    ) {
        self.repository = repository
        self.historyDidChange = historyDidChange
    }

    /// 登録車両のVINと大文字小文字を区別せず一致する未紐付けセッションへ車両を設定します。
    ///
    /// 責務: 1台の登録車両を、同じVINを観測した未紐付けセッションへの車両設定件数へ変換します。
    /// 1件以上更新した場合だけ履歴更新を1回通知します。
    /// - Parameters:
    ///   - vehicle: セッションへ設定する登録済み車両。VINの前後の空白は照合前に除きます。
    ///   - accountIdentifier: 更新対象のAppleアカウント識別子。
    /// - Returns: 車両を設定したセッション件数。VINが空、または一致が無い場合は `0`。
    /// - Throws: 保存先を利用できない、または更新に失敗した場合のエラー。
    func execute(vehicle: VehicleProfile, accountIdentifier: String) throws -> Int {
        guard let vin = ConnectionSession.normalizedObservedVIN(vehicle.vin) else { return 0 }
        let assignedCount = try repository.assignVehicle(
            ConnectionSessionVehicle(profile: vehicle),
            toUnassignedSessionsWithObservedVIN: vin,
            for: accountIdentifier
        )
        if assignedCount > 0 { historyDidChange() }
        return assignedCount
    }
}
