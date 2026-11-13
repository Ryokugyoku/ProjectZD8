#if os(iOS)
import SwiftUI

/// ドライブ画面です。記録の段階に応じて、待機・進行・ダッシュボードを切り替えます。
struct IOSDriveScreen: View {
    let drive: DriveSessionState
    let devices: DeviceConnectionState
    let live: LiveTelemetryState
    let sendDrive: (DriveSessionAction) -> Void
    let sendDevice: (DeviceConnectionAction) -> Void
    let sendLive: (LiveTelemetryAction) -> Void

    @State private var isAdapterPickerPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .frame(maxWidth: IOSAppShellMetrics.contentMaxWidth)
                    .padding(.horizontal, InsightSpacing.screenGutter)
                    .padding(.vertical, InsightSpacing.lg)
                    .frame(maxWidth: .infinity)
            }
            .background(InsightBackground())
            .navigationTitle(Text("tab.drive"))
            .task(id: drive.phase.isIdle) {
                if drive.phase.isIdle, devices.discovery == .idle { sendDevice(.discoverRequested) }
            }
        }
        .sheet(isPresented: $isAdapterPickerPresented) {
            IOSAdapterPickerSheet(state: devices, send: sendDevice) { isAdapterPickerPresented = false }
        }
        .sheet(isPresented: registrationBinding) {
            if case .awaitingVehicleRegistration(let identification) = drive.phase {
                IOSVehicleRegistrationSheet(
                    identification: identification,
                    adapter: drive.adapter,
                    send: sendDrive
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch drive.phase {
        case .recording:
            IOSDriveRecordingContent(drive: drive, live: live, sendDrive: sendDrive)
        case .idle:
            IOSDriveIdleContent(
                drive: drive,
                devices: devices,
                live: live,
                sendDrive: sendDrive,
                sendLive: sendLive,
                onChooseAdapter: { isAdapterPickerPresented = true }
            )
        case .connecting, .identifying, .awaitingVehicleRegistration, .preparing, .stopping:
            IOSDriveProgressCard(drive: drive, sendDrive: sendDrive)
        }
    }

    /// 車両登録待ちの間だけ開くシートの表示です。閉じる操作は登録の取りやめとして扱います。
    private var registrationBinding: Binding<Bool> {
        Binding(
            get: {
                if case .awaitingVehicleRegistration = drive.phase { return true }
                return false
            },
            set: { isPresented in
                if !isPresented { sendDrive(.registrationCancelled) }
            }
        )
    }
}
#endif
