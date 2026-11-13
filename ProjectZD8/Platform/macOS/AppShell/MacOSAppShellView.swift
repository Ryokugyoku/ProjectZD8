#if os(macOS)
import SwiftUI

/// macOS のルート画面。`NavigationSplitView` のサイドバーと各遷移先、共通ツールバー、共通シートを持つ。
///
/// モデルは生成せず、初期化子から受け取る。分析画面は別オーナーの型なのでクロージャで注入する。
struct MacOSAppShellView<AnalysisContent: View>: View {
    @Bindable private var navigation: MacOSNavigationState
    private let deviceConnection: DeviceConnectionModel
    private let driveSession: DriveSessionModel
    private let liveTelemetry: LiveTelemetryModel
    private let vehicles: VehicleManagementModel
    private let maintenance: MaintenanceModel
    private let logHistory: LogHistoryModel
    private let settings: SettingsModel
    private let sync: SyncModel
    private let onAnalysisRequested: (SessionID) -> Void
    private let analysis: () -> AnalysisContent

    /// 責務: ナビゲーション状態・全モデル・分析コンテンツ生成クロージャを受け取って保持する。
    init(
        navigation: MacOSNavigationState,
        deviceConnection: DeviceConnectionModel,
        driveSession: DriveSessionModel,
        liveTelemetry: LiveTelemetryModel,
        vehicles: VehicleManagementModel,
        maintenance: MaintenanceModel,
        logHistory: LogHistoryModel,
        settings: SettingsModel,
        sync: SyncModel,
        onAnalysisRequested: @escaping (SessionID) -> Void,
        @ViewBuilder analysis: @escaping () -> AnalysisContent
    ) {
        self.navigation = navigation
        self.deviceConnection = deviceConnection
        self.driveSession = driveSession
        self.liveTelemetry = liveTelemetry
        self.vehicles = vehicles
        self.maintenance = maintenance
        self.logHistory = logHistory
        self.settings = settings
        self.sync = sync
        self.onAnalysisRequested = onAnalysisRequested
        self.analysis = analysis
    }

    var body: some View {
        NavigationSplitView {
            MacOSSidebarView(
                selection: $navigation.selection,
                isRecording: driveSession.state.activeSession != nil,
                sync: sync.state
            )
        } detail: {
            detail
                .toolbar {
                    MacOSConnectionToolbarContent(
                        drive: driveSession.state,
                        onConnect: requestConnection,
                        onStop: { driveSession.send(.stopRequested) }
                    )
                }
        }
        .frame(minWidth: MacOSAppShellMetrics.windowMinimumSize.width, minHeight: MacOSAppShellMetrics.windowMinimumSize.height)
        .preferredColorScheme(colorScheme)
        .sheet(isPresented: $navigation.isAdapterPickerPresented) {
            MacOSAdapterPickerSheet(
                state: deviceConnection.state,
                isConnectEnabled: driveSession.state.phase.isIdle,
                send: deviceConnection.send,
                onConnect: { adapter in
                    navigation.isAdapterPickerPresented = false
                    navigation.selection = .drive
                    driveSession.send(.connectRequested(adapter))
                },
                onClose: { navigation.isAdapterPickerPresented = false }
            )
        }
        .sheet(isPresented: registrationPresented) {
            if case .awaitingVehicleRegistration(let identification) = driveSession.state.phase {
                MacOSVehicleRegistrationSheet(identification: identification, send: driveSession.send)
            }
        }
        .task {
            deviceConnection.send(.defaultAdapterLoadRequested)
            vehicles.send(.started)
            maintenance.send(.started)
            logHistory.send(.started)
            sync.send(.appeared)
        }
        .onChange(of: logHistory.state.analysisRequest) { _, request in
            guard let request else { return }
            navigation.selection = .analysis
            onAnalysisRequested(request)
            logHistory.send(.analysisRequestHandled)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection {
        case .drive:
            MacOSDriveView(
                deviceConnection: deviceConnection.state,
                drive: driveSession.state,
                telemetry: liveTelemetry.state,
                onConnect: requestConnection,
                onChooseAdapter: { navigation.isAdapterPickerPresented = true },
                sendDrive: driveSession.send,
                sendTelemetry: liveTelemetry.send
            )
        case .logs:
            MacOSLogHistoryView(state: logHistory.state, send: logHistory.send)
        case .analysis:
            analysis()
        case .garage:
            MacOSGarageView(state: vehicles.state, send: vehicles.send)
        case .maintenance:
            MacOSMaintenanceView(state: maintenance.state, send: maintenance.send)
        }
    }

    private var colorScheme: ColorScheme? {
        switch settings.state.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var registrationPresented: Binding<Bool> {
        Binding(
            get: {
                if case .awaitingVehicleRegistration = driveSession.state.phase { return true }
                return false
            },
            set: { isPresented in
                if !isPresented { driveSession.send(.registrationCancelled) }
            }
        )
    }

    private func requestConnection() {
        navigation.requestConnection(deviceConnection: deviceConnection, driveSession: driveSession)
    }
}
#endif
