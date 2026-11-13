/// 車両のPID収集設定画面に並ぶ1項目です。
nonisolated struct VehiclePIDSettingItem: Identifiable, Equatable, Sendable {
    /// Service/PIDの組です。
    let request: OBDPIDRequest
    /// 名称のローカライズキーです。
    let nameKey: String
    /// 変換後の単位です。
    let unit: String
    /// 標準PIDの表示分類です。車種専用PIDでは `nil` です。
    let category: OBDPIDCategory?
    /// 車種専用PIDかどうかです(バッジ表示用)。
    let isVehicleSpecific: Bool
    /// 車両が応答すると確認できたか、していないか、未確認かです。
    let support: PIDSupport
    /// 実際に収集されるかどうかです。応答を確認できていないPIDは `false` です。
    let isEnabled: Bool

    /// `Identifiable` が使用する識別値です。
    var id: OBDPIDRequest { request }
    /// 車両が応答すると確認できたかどうかです。
    var isSupported: Bool { support == .supported }
}
