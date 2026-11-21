/// 位置情報の利用許可の読取と要求の境界です。
@MainActor
protocol LocationAuthorizationPort: AnyObject {
    /// 現在の許可状態。
    var currentPermission: LocationPermission { get }

    /// 許可状態の変化の流れを返します。
    ///
    /// 責務: 許可状態が変わるたびに新しい状態を流します。消費者は配線型の1つだけです。
    /// - Returns: 許可状態の流れ。
    func permissionChanges() -> AsyncStream<LocationPermission>

    /// 「使用中のみ」の許可を要求します。
    ///
    /// 責務: システムの許可確認を1回要求します。
    func requestWhenInUseAuthorization()

    /// 「常に許可」を要求します。
    ///
    /// 責務: システムの昇格確認を1回要求します。
    func requestAlwaysAuthorization()
}
