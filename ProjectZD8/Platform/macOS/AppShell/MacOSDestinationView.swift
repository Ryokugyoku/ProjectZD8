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

    /// リアルタイムログ画面へ渡す主要PID読取状態です。
    let liveTelemetryState: LiveTelemetryState

    /// HOMEの操作をAppShellへ通知するクロージャです。
    let sendHomeAction: (MacOSHomeAction) -> Void

    /// 設定画面の操作をAppShellへ通知するクロージャです。
    let sendSettingsAction: (MacOSSettingsAction) -> Void

    /// アカウント同期対象の設定操作を通知するクロージャです。
    let sendAccountSettingsAction: (AccountSettingsAction) -> Void

    /// Garageの型付き操作をVehicleManagementへ通知します。
    let sendVehicleManagementAction: (VehicleManagementAction) -> Void

    /// 主要PID読取操作をLiveTelemetryへ通知します。
    let sendLiveTelemetryAction: (LiveTelemetryAction) -> Void

    /// Authenticationが管理するアカウント削除の現在段階です。
    let accountDeletionPhase: AccountDeletionPhase

    /// Authenticationが保持する直近のアカウント削除失敗です。
    let accountDeletionFailure: AccountDeletionFailure?

    /// アカウント削除の型付き操作をAuthenticationへ通知します。
    let sendAuthenticationAction: (AuthenticationAction) -> Void

    /// 選択された遷移先に対応するmacOS画面を提供します。
    ///
    /// 責務: 現在の遷移先を専用画面または識別用プレースホルダーへ振り分けます。
    @ViewBuilder
    var body: some View {
        if destination == .home {
            MacOSHomeView(
                state: MacOSHomeState(settingsState: settingsState),
                send: sendHomeAction,
                metrics: metrics
            )
        } else if destination == .liveLog {
            MacOSLiveTelemetryView(
                state: liveTelemetryState,
                send: sendLiveTelemetryAction,
                metrics: metrics
            )
        } else if destination == .garage {
            MacOSGarageView(
                state: vehicleManagementState,
                send: sendVehicleManagementAction,
                metrics: metrics
            )
        } else if destination == .settings {
            MacOSSettingsView(
                state: settingsState,
                accountSettings: accountSettings,
                send: sendSettingsAction,
                sendAccountSettingsAction: sendAccountSettingsAction,
                accountDeletionPhase: accountDeletionPhase,
                accountDeletionFailure: accountDeletionFailure,
                sendAuthenticationAction: sendAuthenticationAction,
                metrics: metrics
            )
        } else {
            placeholder
        }
    }

    /// 未実装の遷移先を識別できるプレースホルダーです。
    private var placeholder: some View {
        VStack(spacing: 22 * metrics.scale) {
            Image(systemName: destination.systemImage)
                .font(.system(size: metrics.contentSymbolSize, weight: .medium))
                .foregroundStyle(.tint)

            Text(destination.title)
                .font(.system(size: metrics.contentTitleSize, weight: .bold))

            Text("shell.destination.placeholder")
                .font(.system(size: 15 * metrics.scale))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32 * metrics.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("macos-destination-\(destination.rawValue)")
    }
}
#endif
