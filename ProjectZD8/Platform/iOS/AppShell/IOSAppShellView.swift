#if os(iOS)
import SwiftUI

/// iOS / iPadOS のアプリ全体の骨格です。ドライブ・ログ・ガレージ・設定の4タブを持ちます。
///
/// モデルは生成せず、イニシャライザで受け取ります。分析画面は別の担当が作るため、ビルダーで注入します。
struct IOSAppShellView<AnalysisContent: View>: View {
    private let deviceConnection: DeviceConnectionModel
    private let driveSession: DriveSessionModel
    private let liveTelemetry: LiveTelemetryModel
    private let vehicles: VehicleManagementModel
    private let maintenance: MaintenanceModel
    private let logHistory: LogHistoryModel
    private let settings: SettingsModel
    private let sync: SyncModel
    private let analysis: (SessionID) -> AnalysisContent

    @State private var selection: IOSAppTab = .drive
    @State private var presentedAnalysis: SessionID?

    /// 責務: 各機能のモデルと分析画面のビルダーを受け取ります。
    /// - Parameter analysis: 指定セッションの分析画面を返すビルダー。
    init(
        deviceConnection: DeviceConnectionModel,
        driveSession: DriveSessionModel,
        liveTelemetry: LiveTelemetryModel,
        vehicles: VehicleManagementModel,
        maintenance: MaintenanceModel,
        logHistory: LogHistoryModel,
        settings: SettingsModel,
        sync: SyncModel,
        @ViewBuilder analysis: @escaping (SessionID) -> AnalysisContent
    ) {
        self.deviceConnection = deviceConnection
        self.driveSession = driveSession
        self.liveTelemetry = liveTelemetry
        self.vehicles = vehicles
        self.maintenance = maintenance
        self.logHistory = logHistory
        self.settings = settings
        self.sync = sync
        self.analysis = analysis
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("tab.drive", systemImage: "gauge.with.dots.needle.67percent", value: IOSAppTab.drive) {
                IOSDriveView(deviceConnection: deviceConnection, driveSession: driveSession, liveTelemetry: liveTelemetry)
            }
            Tab("tab.logs", systemImage: "list.bullet.rectangle", value: IOSAppTab.logs) {
                IOSLogHistoryView(logHistory: logHistory)
            }
            Tab("tab.garage", systemImage: "car.side", value: IOSAppTab.garage) {
                IOSGarageView(vehicles: vehicles, maintenance: maintenance)
            }
            Tab("tab.settings", systemImage: "gearshape", value: IOSAppTab.settings) {
                IOSSettingsView(settings: settings, deviceConnection: deviceConnection, sync: sync)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewBottomAccessory(isEnabled: recordingSummary != nil) {
            if let summary = recordingSummary {
                IOSRecordingIndicator(summary: summary) { selection = .drive }
            }
        }
        .preferredColorScheme(colorScheme)
        .fullScreenCover(item: $presentedAnalysis) { sessionID in
            IOSAnalysisCover(onClose: { presentedAnalysis = nil }) { analysis(sessionID) }
        }
        .onChange(of: logHistory.state.analysisRequest) { _, request in
            guard let request else { return }
            presentedAnalysis = request
            logHistory.send(.analysisRequestHandled)
        }
        .task {
            vehicles.send(.started)
            maintenance.send(.started)
            logHistory.send(.started)
            sync.send(.appeared)
            deviceConnection.send(.defaultAdapterLoadRequested)
        }
    }

    /// 記録中のセッション要約です。記録中でなければ `nil` です。
    private var recordingSummary: ActiveSessionSummary? {
        driveSession.state.phase == .recording ? driveSession.state.activeSession : nil
    }

    /// 設定の外観を、システム任せの場合は `nil` とした配色へ変換します。
    private var colorScheme: ColorScheme? {
        switch settings.state.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
#endif
