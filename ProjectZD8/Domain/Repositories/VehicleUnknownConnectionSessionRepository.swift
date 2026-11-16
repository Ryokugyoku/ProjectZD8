/// 車両を特定できずに保存した接続セッション(車両なし・観測VINなし、以下「車両不明ログ」)の照会と、登録車両への紐付けの契約です。
///
/// 対象は終了済み(記録中でない)・車両未設定・観測VINなしのセッションだけです。観測VIN付きの未紐付けセッションは
/// `ObservedVINConnectionSessionRepository` が扱い、この契約には含めません。
protocol VehicleUnknownConnectionSessionRepository {
    /// 指定アカウントの車両不明ログを新しい順で返します。
    ///
    /// 責務: 終了済み・車両未設定・観測VINなしのセッションだけを照会します。
    /// - Parameter accountIdentifier: 取得対象のAppleアカウント識別子。
    /// - Returns: 開始日時が新しい順の車両不明ログ。
    /// - Throws: 保存先を使えない場合や保存値が不正な場合のエラー。
    func vehicleUnknownSessions(for accountIdentifier: String) throws -> [ConnectionSession]

    /// 指定した車両不明ログへ登録車両を設定します。
    ///
    /// 責務: 指定IDのうち、指定アカウントの終了済み・車両未設定・観測VINなしの行だけを更新します(対象外の行は変えません)。
    /// - Parameters:
    ///   - vehicle: 設定する登録車両の表示情報。
    ///   - sessionIDs: 紐付けるセッションのID。
    ///   - accountIdentifier: 更新対象のAppleアカウント識別子。
    /// - Returns: 車両を設定したセッション件数。
    /// - Throws: 保存先を使えない場合や更新に失敗した場合のエラー。
    func assignVehicle(
        _ vehicle: ConnectionSessionVehicle,
        toVehicleUnknownSessions sessionIDs: [ConnectionSessionID],
        for accountIdentifier: String
    ) throws -> Int
}
