#if os(iOS)
import SwiftUI

/// 選択されたiOS遷移先に対応する画面を描画します。
struct IOSDestinationView: View {
    /// この画面が表す遷移先です。
    let destination: IOSAppShellDestination

    /// 設定画面へ渡す現在の表示設定です。
    let settingsState: IOSSettingsState

    /// 設定画面へ渡す現在のアカウント同期対象設定です。
    let accountSettings: AccountSettings

    /// HOME登録導線とGarageへ渡す現在の車両管理状態です。
    let vehicleManagementState: VehicleManagementState

    /// 整備画面へ渡す現在の車両別整備状態です。
    let maintenanceState: MaintenanceState

    /// ホームのリアルタイム表示パネルとホームの配置判定へ渡すPID読取状態です。
    let liveTelemetryState: LiveTelemetryState

    /// ホームのセッション見出しへ渡す記録中の接続セッションです。記録していなければ `nil` です。
    let activeConnectionSession: ConnectionSession?

    /// 接続履歴画面へ渡す現在の履歴状態です。
    let connectionHistoryState: ConnectionHistoryState

    /// 接続履歴内のPID解析画面へ渡す状態です。
    let sessionLogAnalysisState: SessionLogAnalysisState

    /// HOMEの操作をAppShellへ通知するクロージャです。
    let sendHomeAction: (IOSHomeAction) -> Void

    /// 設定画面の操作をAppShellへ通知するクロージャです。
    let sendSettingsAction: (IOSSettingsAction) -> Void

    /// アカウント同期対象の設定操作を通知するクロージャです。
    let sendAccountSettingsAction: (AccountSettingsAction) -> Void

    /// 車両登録・編集操作をVehicleManagementへ通知します。
    let sendVehicleManagementAction: (VehicleManagementAction) -> Void

    /// 軽整備・重整備操作をMaintenanceへ通知します。
    let sendMaintenanceAction: (MaintenanceAction) -> Void

    /// 主要PID読取操作をLiveTelemetryへ通知します。
    let sendLiveTelemetryAction: (LiveTelemetryAction) -> Void

    /// 接続履歴操作をLogHistoryへ通知します。
    let sendConnectionHistoryAction: (ConnectionHistoryAction) -> Void

    /// PID解析操作をAnalysisへ通知します。
    let sendSessionLogAnalysisAction: (SessionLogAnalysisAction) -> Void

    /// 設定画面の「車両検知時の記録開始」区画に表示する内容です。
    let automaticRecordingSection: AutomaticRecordingSettingsSection

    /// 記録開始方法の操作を自動記録設定モデルへ通知するクロージャです。
    let sendAutomaticRecordingAction: (AutomaticRecordingPreferenceAction) -> Void

    /// 設定画面の「走行ルートを記録」区画に表示する内容です。
    let routeRecordingSection: RouteRecordingSettingsSection

    /// 「走行ルートを記録」の操作を設定モデルへ通知するクロージャです。
    let sendRouteRecordingAction: (RouteRecordingSettingsAction) -> Void

    /// 設定画面の「エンジン停止とみなす時間」区画に表示する内容です。
    let vehicleOffSection: VehicleOffDetectionSettingsSection

    /// 「エンジン停止とみなす時間」の操作を設定モデルへ通知するクロージャです。
    let sendVehicleOffAction: (VehicleOffDetectionDelayAction) -> Void

    /// ホームと車両画面に表示する未登録車両の警告です。
    let unassignedVINWarning: UnassignedObservedVINWarning

    /// 未登録車両の警告の主要操作をAppShellへ通知するクロージャです。
    let sendUnassignedVINWarningAction: (UnassignedObservedVINWarningPrimaryAction) -> Void

    /// ホームと車両画面に表示する、車両を特定できなかったログの警告です。
    let vehicleUnknownSessionWarning: VehicleUnknownSessionWarning

    /// 車両不明ログの警告の主要操作をAppShellへ通知するクロージャです。
    let sendVehicleUnknownSessionWarningAction: (VehicleUnknownSessionWarningPrimaryAction) -> Void

    /// Authenticationが管理するアカウント削除の現在段階です。
    let accountDeletionPhase: AccountDeletionPhase

    /// Authenticationが保持する直近のアカウント削除失敗です。
    let accountDeletionFailure: AccountDeletionFailure?

    /// アカウント削除の型付き操作をAuthenticationへ通知します。
    let sendAuthenticationAction: (AuthenticationAction) -> Void

    /// 選択された遷移先に対応するiOS画面を提供します。
    ///
    /// 責務: 現在の遷移先をiOS専用のFeature画面へ振り分けます。
    @ViewBuilder
    var body: some View {
        switch destination {
        case .home:
            homeContent
        case .history:
            IOSConnectionHistoryView(
                state: connectionHistoryState,
                send: sendConnectionHistoryAction,
                analysisState: sessionLogAnalysisState,
                sendAnalysis: sendSessionLogAnalysisAction
            )
        case .maintenance:
            IOSMaintenanceView(state: maintenanceState, send: sendMaintenanceAction)
        case .garage:
            IOSGarageView(state: vehicleManagementState, send: sendVehicleManagementAction)
                .safeAreaInset(edge: .top, spacing: 0) { unassignedVINWarningInset }
        case .settings:
            settingsContent
        }
    }

    /// ホームの遷移先の画面です。車両の識別・登録の最中は登録画面を、それ以外はリアルタイム表示を差し込んだホームを出します。
    @ViewBuilder
    private var homeContent: some View {
        if [.identifying, .confirmingIdentification, .registering, .failed].contains(vehicleManagementState.phase) {
            IOSVehicleRegistrationView(
                state: vehicleManagementState,
                send: sendVehicleManagementAction
            )
        } else {
            IOSHomeView(
                state: IOSHomeState(
                    settingsState: settingsState,
                    liveTelemetryState: liveTelemetryState,
                    activeSession: activeConnectionSession,
                    vehicles: vehicleManagementState.vehicles
                ),
                send: sendHomeAction
            ) {
                IOSLiveTelemetryPanel(state: liveTelemetryState, send: sendLiveTelemetryAction)
            }
            .safeAreaInset(edge: .top, spacing: 0) { unassignedVINWarningInset }
        }
    }

    /// 設定の遷移先の画面です。
    private var settingsContent: some View {
        IOSSettingsView(
            state: settingsState,
            accountSettings: accountSettings,
            send: sendSettingsAction,
            sendAccountSettingsAction: sendAccountSettingsAction,
            automaticRecordingSection: automaticRecordingSection,
            sendAutomaticRecordingAction: sendAutomaticRecordingAction,
            routeRecordingSection: routeRecordingSection,
            sendRouteRecordingAction: sendRouteRecordingAction,
            vehicleOffSection: vehicleOffSection,
            sendVehicleOffAction: sendVehicleOffAction,
            accountDeletionPhase: accountDeletionPhase,
            accountDeletionFailure: accountDeletionFailure,
            sendAuthenticationAction: sendAuthenticationAction
        )
    }

    /// ホームと車両画面の上端に重ねる未登録車両の警告と、車両を特定できなかったログの警告(別枠)です。
    /// 識別・登録・編集の最中は表示しません。
    @ViewBuilder
    private var unassignedVINWarningInset: some View {
        VStack(spacing: 0) {
            if IOSUnassignedObservedVINWarningVisibility.isVisible(
                warning: unassignedVINWarning,
                vehiclePhase: vehicleManagementState.phase
            ) {
                IOSUnassignedObservedVINWarningCard(warning: unassignedVINWarning, send: sendUnassignedVINWarningAction)
                    .padding(.horizontal, IOSUnassignedObservedVINWarningMetrics.horizontalInset)
                    .padding(.top, IOSUnassignedObservedVINWarningMetrics.topInset)
            }
            if IOSVehicleUnknownSessionWarningVisibility.isVisible(
                warning: vehicleUnknownSessionWarning,
                vehiclePhase: vehicleManagementState.phase
            ) {
                IOSVehicleUnknownSessionWarningCard(warning: vehicleUnknownSessionWarning, send: sendVehicleUnknownSessionWarningAction)
                    .padding(.horizontal, IOSVehicleUnknownSessionMetrics.horizontalInset)
                    .padding(.top, IOSVehicleUnknownSessionMetrics.topInset)
            }
        }
    }
}
#endif
