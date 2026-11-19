/// ホーム画面の配置とアダプターカード・セッション見出しの表示内容です。
///
/// iOSとmacOSで共通の判定です。OSごとの接続先の規則は呼び出し側が `connectionEndpoint` に反映します。
struct HomeScreenState: Equatable {
    /// 画面の配置です。
    let layout: HomeScreenLayout
    /// アダプターカードの内容です。配置にかかわらず常に計算します。
    let adapterCard: HomeAdapterCardContent
    /// セッション見出しの内容です。接続中の配置の時だけ値を持ちます。
    let sessionHeader: HomeSessionHeaderContent?

    /// アダプターの接続可否・リアルタイム表示の状態・記録中のセッション・登録車両からホームの内容を生成します。
    ///
    /// 責務: 接続中かどうかで配置を選び、配置に必要なカードと見出しの内容を組み立てます。
    /// - Parameters:
    ///   - defaultAdapterAvailability: 保存済みアダプターの現在の接続可否。
    ///   - connectionEndpoint: OSごとの規則で選んだ接続先。接続できなければ `nil`。
    ///   - telemetry: 現在のリアルタイム表示状態。
    ///   - activeSession: 記録中の接続セッション。なければ `nil`。
    ///   - vehicles: 登録済み車両の一覧。
    init(
        defaultAdapterAvailability: DefaultAdapterAvailability,
        connectionEndpoint: OBDConnectionEndpoint?,
        telemetry: LiveTelemetryState,
        activeSession: ConnectionSession?,
        vehicles: [VehicleProfile]
    ) {
        layout = telemetry.isConnectionActive ? .connectedSession : .adapterSetup
        adapterCard = HomeAdapterCardContent(availability: defaultAdapterAvailability, connectionEndpoint: connectionEndpoint)
        sessionHeader = layout == .connectedSession
            ? HomeSessionHeaderContent(telemetry: telemetry, activeSession: activeSession, vehicles: vehicles)
            : nil
    }
}
