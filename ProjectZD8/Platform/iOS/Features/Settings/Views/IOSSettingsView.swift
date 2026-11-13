#if os(iOS)
import SwiftUI

/// 設定タブの入口です。モデルの状態を読み、操作を送るだけで何も所有しません。
struct IOSSettingsView: View {
    let settings: SettingsModel
    let deviceConnection: DeviceConnectionModel
    let sync: SyncModel

    var body: some View {
        IOSSettingsScreen(
            settings: settings.state,
            devices: deviceConnection.state,
            sync: sync.state,
            sendSettings: { settings.send($0) },
            sendDevice: { deviceConnection.send($0) },
            sendSync: { sync.send($0) }
        )
    }
}
#endif
