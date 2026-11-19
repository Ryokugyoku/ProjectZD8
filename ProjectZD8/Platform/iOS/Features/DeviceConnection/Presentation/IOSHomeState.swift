#if os(iOS)
/// iOSホームの表示状態です。iOSの接続先の規則だけを持ち、配置と内容は共通の `HomeScreenState` に任せます。
struct IOSHomeState: Equatable {
    /// デフォルトアダプターの設定、未検出、接続可能を区別する共通状態です。
    let defaultAdapterAvailability: DefaultAdapterAvailability
    /// ホームの配置、アダプターカード、セッション見出しの内容です。
    let screen: HomeScreenState

    /// iOSの設定状態、PID取得状態、記録中のセッション、登録車両からホームの表示状態を作ります。
    ///
    /// 責務: iOSの設定状態をデフォルトアダプターの状態へ縮約し、iOSの接続先の規則で共通のホーム表示状態を作ります。
    /// - Parameters:
    ///   - settingsState: 現在のiOS設定表示状態。
    ///   - liveTelemetryState: 接続中かどうかと車両の判定に使うPID取得状態。
    ///   - activeSession: 記録中の接続セッション。記録していなければ `nil`。
    ///   - vehicles: 車両名の解決に使う登録車両。
    init(
        settingsState: IOSSettingsState,
        liveTelemetryState: LiveTelemetryState = .init(),
        activeSession: ConnectionSession? = nil,
        vehicles: [VehicleProfile] = []
    ) {
        let availability = DefaultAdapterAvailability(
            preference: settingsState.defaultAdapterPreference,
            detectedAdapter: settingsState.selectedAdapters[.primary]
        )
        defaultAdapterAvailability = availability
        screen = HomeScreenState(
            defaultAdapterAvailability: availability,
            connectionEndpoint: availability.connectionEndpoint,
            telemetry: liveTelemetryState,
            activeSession: activeSession,
            vehicles: vehicles
        )
    }
}
#endif
