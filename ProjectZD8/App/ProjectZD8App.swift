import SwiftUI

/// ProjectZD8のプロセスエントリーポイントとプラットフォーム別ルート画面を構築します。
@main
struct ProjectZD8App: App {
    #if os(iOS)
    /// iOS設定画面へ注入するプレゼンテーションモデルです。
    @State private var iOSSettingsModel: IOSSettingsPresentationModel
    #endif

    #if os(macOS)
    /// macOS設定画面へ注入するプレゼンテーションモデルです。
    @State private var macOSSettingsModel: MacOSSettingsPresentationModel
    #endif

    /// プラットフォーム固有の依存関係を組み立ててアプリを生成します。
    ///
    /// 責務: 現在のプラットフォームの実デバイス探索をApplicationユースケースと設定プレゼンテーションへ注入します。
    init() {
        #if os(iOS)
        _iOSSettingsModel = State(
            initialValue: IOSApplicationComposition.makeSettingsPresentationModel()
        )
        #endif

        #if os(macOS)
        let discovery = MacOSSystemAdapterDiscovery()
        let discoverAdapters = DiscoverAdaptersUseCase(discoveryPort: discovery)
        let latestDiscovery = LatestAdapterDiscoveryUseCase(discoverAdapters: discoverAdapters)
        _macOSSettingsModel = State(
            initialValue: MacOSSettingsPresentationModel(
                state: MacOSSettingsState(),
                latestDiscovery: latestDiscovery
            )
        )
        #endif
    }

    /// 現在のプラットフォームが所有するルート画面をアプリケーションウインドウへ配置します。
    ///
    /// 責務: 現在のAppleプラットフォームを独立したAppShellへ結び付けます。
    var body: some Scene {
        WindowGroup {
#if os(iOS)
            IOSAppShellView(settingsModel: iOSSettingsModel)
#elseif os(macOS)
            MacOSAppShellView(settingsModel: macOSSettingsModel)
#endif
        }
    }
}
