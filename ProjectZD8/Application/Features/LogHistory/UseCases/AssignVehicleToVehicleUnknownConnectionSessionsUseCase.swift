/// 車両を特定できずに保存したログを、ユーザーが選んだ登録済みの車両へ紐付けます。
///
/// 紐付けの後は、VINが一致するログを紐付ける既存の処理(`AssignVehicleToObservedVINConnectionSessionsUseCase`)と同じく、
/// 1件以上更新した時だけ履歴の再読込を通知します(既存の処理も同期状態・クラウド上の概要は更新しません)。
struct AssignVehicleToVehicleUnknownConnectionSessionsUseCase {
    /// 車両不明ログの保存先です。
    private let repository: any VehicleUnknownConnectionSessionRepository
    /// 履歴が変わったことを通知する処理です。
    private let historyDidChange: @MainActor () -> Void

    /// 保存先と履歴の変更通知を固定して生成します。
    ///
    /// 責務: 紐付けの更新先と後続の再読込通知を結び付けます。
    /// - Parameters:
    ///   - repository: 車両不明ログの保存先。
    ///   - historyDidChange: 1件以上紐付けた後に呼ぶ処理(履歴の再読込)。
    init(
        repository: any VehicleUnknownConnectionSessionRepository,
        historyDidChange: @escaping @MainActor () -> Void = {}
    ) {
        self.repository = repository
        self.historyDidChange = historyDidChange
    }

    /// 選んだログへ車両を設定します。
    ///
    /// 責務: 保存先へ紐付けを依頼し、1件以上更新したら履歴の変更を通知します。
    /// - Parameters:
    ///   - vehicle: 紐付ける登録済みの車両。
    ///   - sessionIDs: 紐付けるログのID。
    ///   - accountIdentifier: 対象のAppleアカウント識別子。
    /// - Returns: 紐付けた件数(対象外のログは数えません)。
    /// - Throws: 保存先の更新失敗。
    @MainActor
    func execute(vehicle: VehicleProfile, sessionIDs: [ConnectionSessionID], accountIdentifier: String) throws -> Int {
        let assignedCount = try repository.assignVehicle(
            ConnectionSessionVehicle(profile: vehicle),
            toVehicleUnknownSessions: sessionIDs,
            for: accountIdentifier
        )
        if assignedCount > 0 { historyDidChange() }
        return assignedCount
    }
}
