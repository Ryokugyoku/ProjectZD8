#if os(macOS)
/// macOSホームの表示状態です。macOSの接続先の規則(USBに限る)だけを持ち、配置と内容は共通の `HomeScreenState` に任せます。
struct MacOSHomeState: Equatable {
    /// デフォルトアダプターの設定、未検出、接続可能を区別する共通状態です。
    let defaultAdapterAvailability: DefaultAdapterAvailability
    /// macOSで現在利用できるシリアル接続終端です。デフォルト設定に一致するUSBアダプターがある時だけ値を持ちます。
    let connectionEndpoint: OBDConnectionEndpoint?
    /// ホームの配置、アダプターカード、セッション見出しの内容です。
    let screen: HomeScreenState

    /// macOSの設定状態、PID取得状態、記録中のセッション、登録車両からホームの表示状態を作ります。
    ///
    /// 責務: macOSの設定状態をデフォルトアダプターの状態へ縮約し、USBに限る接続先の規則で共通のホーム表示状態を作ります。
    /// - Parameters:
    ///   - settingsState: 現在のmacOS設定表示状態。
    ///   - liveTelemetryState: 接続中かどうかと車両の判定に使うPID取得状態。
    ///   - activeSession: 記録中の接続セッション。記録していなければ `nil`。
    ///   - vehicles: 車両名の解決に使う登録車両。
    init(
        settingsState: MacOSSettingsState,
        liveTelemetryState: LiveTelemetryState = .init(),
        activeSession: ConnectionSession? = nil,
        vehicles: [VehicleProfile] = []
    ) {
        let availability = DefaultAdapterAvailability(
            preference: settingsState.defaultAdapterPreference,
            detectedAdapter: settingsState.selectedAdapters[.primary]
        )
        let endpoint = Self.usbConnectionEndpoint(settingsState: settingsState)
        defaultAdapterAvailability = availability
        connectionEndpoint = endpoint
        screen = HomeScreenState(
            defaultAdapterAvailability: availability,
            connectionEndpoint: endpoint,
            telemetry: liveTelemetryState,
            activeSession: activeSession,
            vehicles: vehicles
        )
    }

    /// デフォルト設定に一致するUSBのプライマリーアダプターから接続先を作ります。
    ///
    /// 責務: macOSで接続できるのはUSB接続のアダプターだけという規則を接続先の有無へ反映します。
    /// - Parameter settingsState: 現在のmacOS設定表示状態。
    /// - Returns: 接続先。プライマリーがない、デフォルト設定と一致しない、USBでない場合は `nil`。
    private static func usbConnectionEndpoint(settingsState: MacOSSettingsState) -> OBDConnectionEndpoint? {
        guard
            let adapter = settingsState.selectedAdapters[.primary],
            settingsState.defaultAdapterPreference?.matches(adapter) == true,
            adapter.transportMode == .usb
        else { return nil }
        return OBDConnectionEndpoint(adapter: adapter)
    }
}
#endif
