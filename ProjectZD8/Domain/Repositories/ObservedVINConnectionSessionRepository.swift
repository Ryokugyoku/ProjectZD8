/// 車両未確定のまま観測VIN付きで記録した接続セッションを照会し、登録車両へ紐付けます。
protocol ObservedVINConnectionSessionRepository {
    /// 指定アカウントで車両未設定かつ観測VINを持つセッションを新しい順で取得します。
    ///
    /// 責務: 1件のアカウントに属する未紐付けの観測VIN付きセッションを開始日時の降順で返します。
    /// - Parameter accountIdentifier: 取得対象のAppleアカウント識別子。
    /// - Returns: `vehicle == nil` かつ `observedVIN != nil` のセッション。開始日時が新しい順。
    /// - Throws: 保存先を利用できない、または保存値が不正な場合の `ConnectionSessionRepositoryError` または保存先エラー。
    func unassignedSessionsWithObservedVIN(for accountIdentifier: String) throws -> [ConnectionSession]

    /// 指定VINを観測した未紐付けセッションへ登録車両を1トランザクションで設定します。
    ///
    /// 責務: 1件のアカウントで車両未設定かつ観測VINが大文字小文字を区別せず一致する全セッションへ車両を設定します。
    /// 既に車両を設定済みのセッションは変更せず、観測VINは保持したままにします。
    /// - Parameters:
    ///   - vehicle: セッションへ設定する登録車両の表示情報。
    ///   - observedVIN: 照合する観測VIN。前後の空白は照合前に除きます。
    ///   - accountIdentifier: 更新対象のAppleアカウント識別子。
    /// - Returns: 車両を設定したセッション件数。一致がない場合は `0`。
    /// - Throws: VINが空白だけの場合は `ConnectionSessionRepositoryError.invalidState`、
    ///   保存先を利用できない場合は `ConnectionSessionRepositoryError.unavailable` または保存先エラー。
    func assignVehicle(
        _ vehicle: ConnectionSessionVehicle,
        toUnassignedSessionsWithObservedVIN observedVIN: String,
        for accountIdentifier: String
    ) throws -> Int
}
