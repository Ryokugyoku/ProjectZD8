/// 車両が走行に使用するエネルギー源を表します。
enum VehicleEnergySource: String, CaseIterable, Codable, Sendable {
    /// ガソリンです。
    case gasoline
    /// ハイオク（プレミアムガソリン）です。
    case gasolinePremium
    /// レギュラー（通常ガソリン）です。
    case gasolineRegular
    /// 軽油です。
    case diesel
    /// 液化石油ガスです。
    case lpg
    /// 圧縮天然ガスです。
    case cng
    /// 水素です。
    case hydrogen
    /// 電力です。
    case electricity
    /// 既知の選択肢に該当しないエネルギー源です。
    case other
}
