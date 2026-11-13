#if os(macOS)
import SwiftUI

/// メニューバーのコマンド(遷移ショートカット・接続 / 停止・今すぐ同期・更新)。
struct MacOSAppCommands: Commands {
    private let navigation: MacOSNavigationState
    private let deviceConnection: DeviceConnectionModel
    private let driveSession: DriveSessionModel
    private let vehicles: VehicleManagementModel
    private let maintenance: MaintenanceModel
    private let logHistory: LogHistoryModel
    private let sync: SyncModel

    /// 責務: コマンドが操作する共有状態とモデルを受け取って保持する。
    init(
        navigation: MacOSNavigationState,
        deviceConnection: DeviceConnectionModel,
        driveSession: DriveSessionModel,
        vehicles: VehicleManagementModel,
        maintenance: MaintenanceModel,
        logHistory: LogHistoryModel,
        sync: SyncModel
    ) {
        self.navigation = navigation
        self.deviceConnection = deviceConnection
        self.driveSession = driveSession
        self.vehicles = vehicles
        self.maintenance = maintenance
        self.logHistory = logHistory
        self.sync = sync
    }

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(MacOSDestination.allCases) { destination in
                Button {
                    navigation.selection = destination
                } label: {
                    Text(destination.titleKey)
                }
                .keyboardShortcut(destination.shortcutKey, modifiers: .command)
            }
        }
        CommandMenu(Text("commands.drive.menu")) {
            if driveSession.state.phase.isIdle {
                Button {
                    navigation.requestConnection(deviceConnection: deviceConnection, driveSession: driveSession)
                } label: {
                    Text("drive.connect")
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            } else {
                Button {
                    driveSession.send(.stopRequested)
                } label: {
                    Text("drive.stop")
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(driveSession.state.phase == .stopping)
            }
            Divider()
            Button {
                sync.send(.syncNowTapped)
            } label: {
                Text("sync.action.syncNow")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!sync.state.canSyncNow)
        }
        CommandGroup(after: .toolbar) {
            Button {
                refresh()
            } label: {
                Text("commands.refresh")
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    /// 責務: 現在の遷移先に応じたモデルへ更新を要求する。
    private func refresh() {
        switch navigation.selection {
        case .drive: deviceConnection.send(.discoverRequested)
        case .logs: logHistory.send(.refreshRequested)
        case .analysis: break
        case .garage: vehicles.send(.refreshRequested)
        case .maintenance: maintenance.send(.refreshRequested)
        }
    }
}
#endif
