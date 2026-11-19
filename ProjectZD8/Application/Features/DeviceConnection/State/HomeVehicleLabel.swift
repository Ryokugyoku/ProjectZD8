/// ホームのセッション見出しに出す車両の表し方です。
nonisolated enum HomeVehicleLabel: Equatable, Sendable {
    /// 登録済み車両の名称です。前後の空白を除いた空でない文字列だけを持ちます。
    case named(String)
    /// 未登録の車両です。
    case unregistered
    /// 名称を決められない車両です。
    case unnamed

    /// 名称の代わりに出すローカライズキーです。
    ///
    /// 責務: 名称を持たない表し方を文言キーへ変換します。
    /// - Returns: 未登録・名称なしなら文言キー。名称を持つ場合は `nil`。
    var localizationKey: String? {
        switch self {
        case .named: nil
        case .unregistered: "home.vehicle.unregistered"
        case .unnamed: "home.vehicle.unnamed"
        }
    }
}
