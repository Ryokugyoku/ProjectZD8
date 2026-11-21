#if os(macOS)
import SwiftUI

/// 選択されたmacOS遷移先に対応する画面を描画します。
struct MacOSDestinationView: View {
    /// この画面が表す遷移先です。
    let destination: MacOSSidebarDestination

    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 設定画面へ渡す現在の表示設定です。
    let settingsState: MacOSSettingsState

    /// 設定画面へ渡す現在のアカウント同期対象設定です。
    let accountSettings: AccountSettings

    /// Garageへ渡す現在の車両管理状態です。
    let vehicleManagementState: VehicleManagementState

    /// 整備画面へ渡す現在の車両別整備状態です。
    let maintenanceState: MaintenanceState

    /// ホームへ差し込むリアルタイム表示パネルとホームの配置判定へ渡す主要PID読取状態です。
    let liveTelemetryState: LiveTelemetryState

    /// ホームのセッション見出しへ渡す記録中の接続セッションです。記録していなければ `nil` です。
    let activeConnectionSession: ConnectionSession?

    /// 接続履歴画面へ渡す現在の履歴状態です。
    let connectionHistoryState: ConnectionHistoryState

    /// 接続履歴内のPID解析画面へ渡す状態です。
    let sessionLogAnalysisState: SessionLogAnalysisState

    /// 接続履歴内のセッション詳細の走行ルート(地図)へ渡す状態です。
    let drivingRouteDetailState: DrivingRouteDetailState

    /// 接続履歴内のPID解析画面の走行ルート(色分けとグラフ連動)へ渡す状態です。
    let routeAnalysisState: RouteAnalysisState

    /// 設定画面の交通規制データのカードと管理画面へ渡す状態です。
    let roadRegulationSettingsState: RoadRegulationSettingsState

    /// 接続履歴内のPID解析画面の交通規制の照合へ渡す状態です。
    let sessionRoadRegulationReviewState: SessionRoadRegulationReviewState

    /// HOMEの操作をAppShellへ通知するクロージャです。
    let sendHomeAction: (MacOSHomeAction) -> Void

    /// 設定画面の操作をAppShellへ通知するクロージャです。
    let sendSettingsAction: (MacOSSettingsAction) -> Void

    /// アカウント同期対象の設定操作を通知するクロージャです。
    let sendAccountSettingsAction: (AccountSettingsAction) -> Void

    /// Garageの型付き操作をVehicleManagementへ通知します。
    let sendVehicleManagementAction: (VehicleManagementAction) -> Void

    /// 軽整備・重整備操作をMaintenanceへ通知します。
    let sendMaintenanceAction: (MaintenanceAction) -> Void

    /// 主要PID読取操作をLiveTelemetryへ通知します。
    let sendLiveTelemetryAction: (LiveTelemetryAction) -> Void

    /// 接続履歴操作をLogHistoryへ通知します。
    let sendConnectionHistoryAction: (ConnectionHistoryAction) -> Void

    /// PID解析操作をAnalysisへ通知します。
    let sendSessionLogAnalysisAction: (SessionLogAnalysisAction) -> Void

    /// 走行ルートの操作をLogHistoryへ通知します。
    let sendDrivingRouteDetailAction: (DrivingRouteDetailAction) -> Void

    /// 解析画面の走行ルートの操作をAnalysisへ通知します。
    let sendRouteAnalysisAction: (RouteAnalysisAction) -> Void

    /// 交通規制データの管理画面の操作をRoadRegulationへ通知します。
    let sendRoadRegulationSettingsAction: (RoadRegulationSettingsAction) -> Void

    /// 解析画面の交通規制の照合の操作をAnalysisへ通知します。
    let sendSessionRoadRegulationReviewAction: (SessionRoadRegulationReviewAction) -> Void

    /// Authenticationが管理するアカウント削除の現在段階です。
    let accountDeletionPhase: AccountDeletionPhase

    /// Authenticationが保持する直近のアカウント削除失敗です。
    let accountDeletionFailure: AccountDeletionFailure?

    /// 設定画面の「エンジン停止とみなす時間」区画に表示する内容です。
    let vehicleOffSection: VehicleOffDetectionSettingsSection

    /// 「エンジン停止とみなす時間」の操作を設定モデルへ通知するクロージャです。
    let sendVehicleOffAction: (VehicleOffDetectionDelayAction) -> Void

    /// アカウント削除の型付き操作をAuthenticationへ通知します。
    let sendAuthenticationAction: (AuthenticationAction) -> Void

    /// 選択された遷移先に対応するmacOS画面を提供します。
    ///
    /// 責務: 現在の遷移先をmacOS専用のFeature画面へ振り分けます。
    @ViewBuilder
    var body: some View {
        switch destination {
        case .home:
            homeContent
        case .history:
            MacOSConnectionHistoryView(
                state: connectionHistoryState,
                send: sendConnectionHistoryAction,
                analysisState: sessionLogAnalysisState,
                sendAnalysis: sendSessionLogAnalysisAction,
                drivingRouteState: drivingRouteDetailState,
                sendDrivingRoute: sendDrivingRouteDetailAction,
                routeAnalysisState: routeAnalysisState,
                sendRouteAnalysis: sendRouteAnalysisAction,
                roadRegulationReviewState: sessionRoadRegulationReviewState,
                sendRoadRegulationReview: sendSessionRoadRegulationReviewAction,
                metrics: metrics
            )
        case .maintenance:
            MacOSMaintenanceView(state: maintenanceState, send: sendMaintenanceAction, metrics: metrics)
        case .garage:
            MacOSGarageView(state: vehicleManagementState, send: sendVehicleManagementAction, metrics: metrics)
        case .settings:
            settingsContent
        }
    }

    /// ホームの遷移先の画面です。リアルタイム表示パネルを差し込んだホームを出します。
    private var homeContent: some View {
        MacOSHomeView(
            state: MacOSHomeState(
                settingsState: settingsState,
                liveTelemetryState: liveTelemetryState,
                activeSession: activeConnectionSession,
                vehicles: vehicleManagementState.vehicles
            ),
            send: sendHomeAction,
            metrics: metrics
        ) {
            MacOSLiveTelemetryPanel(state: liveTelemetryState, send: sendLiveTelemetryAction, metrics: metrics)
        }
    }

    /// 設定の遷移先の画面です。
    private var settingsContent: some View {
        MacOSSettingsView(
            state: settingsState,
            accountSettings: accountSettings,
            send: sendSettingsAction,
            sendAccountSettingsAction: sendAccountSettingsAction,
            vehicleOffSection: vehicleOffSection,
            sendVehicleOffAction: sendVehicleOffAction,
            accountDeletionPhase: accountDeletionPhase,
            accountDeletionFailure: accountDeletionFailure,
            sendAuthenticationAction: sendAuthenticationAction,
            roadRegulationState: roadRegulationSettingsState,
            sendRoadRegulationAction: sendRoadRegulationSettingsAction,
            metrics: metrics
        )
    }
}
#endif
