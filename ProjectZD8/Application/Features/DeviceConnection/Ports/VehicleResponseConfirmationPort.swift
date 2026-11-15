/// 初期化済みのアダプター越しに、車両のECUが応答するかを確認する能力です。
@MainActor
protocol VehicleResponseConfirmationPort: AnyObject {
    /// 指定したタイムアウトでECUの応答を確認します。
    ///
    /// 責務: 1回の問い合わせでECUの応答の有無を判定します。
    /// - Parameter timeout: 通常のタイムアウトかアダプター側の最大タイムアウトか。
    /// - Returns: 応答ありなら `.responding`、タイムアウト内に応答がなければ `.noResponse`。
    /// - Throws: 送受信の失敗・キャンセルなど、応答の有無を判定できなかった場合のエラー。
    func confirmVehicleResponse(timeout: VehicleResponseTimeout) async throws -> VehicleResponseOutcome
}
