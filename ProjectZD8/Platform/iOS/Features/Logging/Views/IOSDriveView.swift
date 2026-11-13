#if os(iOS)
import SwiftUI

/// ドライブタブの入口です。モデルの状態を読み、操作を送るだけで何も所有しません。
struct IOSDriveView: View {
    let deviceConnection: DeviceConnectionModel
    let driveSession: DriveSessionModel
    let liveTelemetry: LiveTelemetryModel

    var body: some View {
        IOSDriveScreen(
            drive: driveSession.state,
            devices: deviceConnection.state,
            live: liveTelemetry.state,
            sendDrive: { driveSession.send($0) },
            sendDevice: { deviceConnection.send($0) },
            sendLive: { liveTelemetry.send($0) }
        )
    }
}
#endif
