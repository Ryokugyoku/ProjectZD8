#if os(macOS)
/// macOS HOMEのアダプター導線に必要な表示専用状態です。
struct MacOSHomeState: Equatable {
    /// デフォルトアダプターの設定、未検出、接続可能を区別する共通状態です。
    let defaultAdapterAvailability: DefaultAdapterAvailability
    /// macOSで現在利用できるシリアル接続終端です。
    let connectionEndpoint: OBDConnectionEndpoint?
    /// PID取得または安全な終了処理が進行中かどうかです。
    let isConnectionActive: Bool
    /// 通信資源の終了完了を待っているかどうかです。
    let isDisconnecting: Bool
    /// BRZ限定の周期接続Betaが有効かどうかです。
    let isBRZBetaActive: Bool
    /// BRZ Betaの危険性に対するユーザー判断が必要かどうかです。
    let requiresBRZBetaConsent: Bool

    /// macOS設定状態からHOME表示状態を生成します。
    ///
    /// 責務: 設定画面のアダプター状態をHOMEの表示専用状態へ縮約します。
    /// - Parameters:
    ///   - settingsState: 現在のmacOS設定表示状態。
    ///   - liveTelemetryState: 接続中判定に使用するPID取得状態。
    init(settingsState: MacOSSettingsState, liveTelemetryState: LiveTelemetryState = .init()) {
        defaultAdapterAvailability = DefaultAdapterAvailability(
            preference: settingsState.defaultAdapterPreference,
            detectedAdapter: settingsState.selectedAdapters[.primary]
        )
        connectionEndpoint = settingsState.selectedAdapters[.primary].flatMap { adapter in
            guard
                settingsState.defaultAdapterPreference?.matches(adapter) == true,
                adapter.transportMode == .usb
            else { return nil }
            return OBDConnectionEndpoint(adapter: adapter)
        }
        isConnectionActive = liveTelemetryState.isConnectionActive
        isDisconnecting = liveTelemetryState.isDisconnecting
        isBRZBetaActive = liveTelemetryState.phase == .loaded
            && liveTelemetryState.acquisitionMode == .brzBetaPeriodic
        requiresBRZBetaConsent = liveTelemetryState.phase == .awaitingBRZBetaConsent
    }
}
#endif
