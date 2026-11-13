#if os(iOS)
/// iOS HOMEのアダプター導線に必要な表示専用状態です。
struct IOSHomeState: Equatable {
    /// デフォルトアダプターの設定、未検出、接続可能を区別する共通状態です。
    let defaultAdapterAvailability: DefaultAdapterAvailability
    /// PID取得または安全な終了処理が進行中かどうかです。
    let isConnectionActive: Bool
    /// 通信資源の終了完了を待っているかどうかです。
    let isDisconnecting: Bool

    /// iOS設定状態からHOME表示状態を生成します。
    ///
    /// 責務: iOS設定画面のアダプター状態をHOMEの表示専用状態へ縮約します。
    /// - Parameters:
    ///   - settingsState: 現在のiOS設定表示状態。
    ///   - liveTelemetryState: 接続中判定に使用するPID取得状態。
    init(settingsState: IOSSettingsState, liveTelemetryState: LiveTelemetryState = .init()) {
        defaultAdapterAvailability = DefaultAdapterAvailability(
            preference: settingsState.defaultAdapterPreference,
            detectedAdapter: settingsState.selectedAdapters[.primary]
        )
        isConnectionActive = liveTelemetryState.isConnectionActive
        isDisconnecting = liveTelemetryState.isDisconnecting
    }
}
#endif
