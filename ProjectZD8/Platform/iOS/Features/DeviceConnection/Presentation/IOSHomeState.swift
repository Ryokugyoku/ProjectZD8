#if os(iOS)
/// iOS HOMEのアダプター導線に必要な表示専用状態です。
struct IOSHomeState: Equatable {
    /// デフォルトアダプターが設定済みかどうかです。
    let hasDefaultAdapter: Bool

    /// デフォルトアダプターとして表示する名称です。
    let defaultAdapterName: String?

    /// デフォルトアダプターが現在のBluetooth探索で検出済みかどうかです。
    let isDefaultAdapterDetected: Bool

    /// iOS設定状態からHOME表示状態を生成します。
    ///
    /// 責務: iOS設定画面のアダプター状態をHOMEの表示専用状態へ縮約します。
    /// - Parameter settingsState: 現在のiOS設定表示状態。
    init(settingsState: IOSSettingsState) {
        hasDefaultAdapter = settingsState.defaultAdapterPreference != nil
        defaultAdapterName = settingsState.defaultAdapterPreference?.displayName
        isDefaultAdapterDetected = settingsState.selectedAdapters[.primary].map {
            settingsState.defaultAdapterPreference?.matches($0) == true
        } ?? false
    }
}
#endif
