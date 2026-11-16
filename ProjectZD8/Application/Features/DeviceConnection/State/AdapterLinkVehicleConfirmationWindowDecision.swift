/// 車両確認の結果(または待ち明け)を受けた時に、確認を続けるか・窓を取り直すか・休止するかの判定結果です。
nonisolated enum AdapterLinkVehicleConfirmationWindowDecision: Equatable, Sendable {
    /// 窓の内で回数の上限にも達していないので、同じ窓で確認を続けます。
    case continueInWindow
    /// 窓は切れたがアプリが前面にいるので、受け取った時刻から窓を取り直して確認を続けます。
    case renewWindow
    /// 窓切れ(背面)か回数の上限に達したので休止します。
    case pause
}
