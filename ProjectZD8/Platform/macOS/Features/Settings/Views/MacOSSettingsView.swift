#if os(macOS)
import SwiftUI

/// SwiftUI の `Settings` シーンに置く設定画面(一般・アダプター・iCloud・情報)。
struct MacOSSettingsView: View {
    private let settings: SettingsModel
    private let deviceConnection: DeviceConnectionModel
    private let sync: SyncModel

    /// 責務: 設定画面が読む3つのモデルを受け取って保持する。
    init(settings: SettingsModel, deviceConnection: DeviceConnectionModel, sync: SyncModel) {
        self.settings = settings
        self.deviceConnection = deviceConnection
        self.sync = sync
    }

    var body: some View {
        TabView {
            Tab {
                MacOSGeneralSettingsView(state: settings.state, send: settings.send)
            } label: {
                Label("settings.tab.general", systemImage: "gearshape")
            }
            Tab {
                MacOSAdapterSettingsView(state: deviceConnection.state, send: deviceConnection.send)
            } label: {
                Label("settings.tab.adapter", systemImage: "cable.connector")
            }
            Tab {
                MacOSICloudSettingsView(state: sync.state, send: sync.send)
            } label: {
                Label("settings.tab.icloud", systemImage: "icloud")
            }
            Tab {
                MacOSAboutSettingsView(versionText: settings.state.versionText)
            } label: {
                Label("settings.tab.about", systemImage: "info.circle")
            }
        }
        .frame(width: MacOSAppShellMetrics.settingsWidth)
        .preferredColorScheme(colorScheme)
        .task {
            deviceConnection.send(.defaultAdapterLoadRequested)
            sync.send(.appeared)
        }
    }

    private var colorScheme: ColorScheme? {
        switch settings.state.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
#endif
