#if os(macOS)
/// macOS HOMEのアダプター導線に必要な表示専用状態です。
struct MacOSHomeState: Equatable {
    /// デフォルトアダプターが設定済みかどうかです。
    let hasDefaultAdapter: Bool

    /// デフォルトアダプターとして表示する名称です。
    let defaultAdapterName: String?

    /// デフォルトアダプターが現在の探索で検出済みかどうかです。
    let isDefaultAdapterDetected: Bool
    /// 接続ボタンからApplicationへ渡すOBD物理終端です。
    let connectionEndpoint: OBDConnectionEndpoint?

    /// macOS設定状態からHOME表示状態を生成します。
    ///
    /// 責務: 設定画面のアダプター状態をHOMEの表示専用状態へ縮約します。
    /// - Parameter settingsState: 現在のmacOS設定表示状態。
    init(settingsState: MacOSSettingsState) {
        hasDefaultAdapter = settingsState.defaultAdapterPreference != nil
        defaultAdapterName = settingsState.defaultAdapterPreference?.displayName
        let detectedAdapter = settingsState.selectedAdapters[.primary].flatMap { adapter in
            settingsState.defaultAdapterPreference?.matches(adapter) == true ? adapter : nil
        }
        isDefaultAdapterDetected = detectedAdapter != nil
        connectionEndpoint = detectedAdapter.flatMap { adapter in
            guard adapter.transportMode == .usb else { return nil }
            return OBDConnectionEndpoint(
                transport: .serial,
                systemIdentifier: adapter.systemIdentifier,
                displayName: adapter.displayName
            )
        }
    }
}
#endif
