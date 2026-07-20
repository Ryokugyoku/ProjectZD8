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

    /// リアルタイムログ画面へ渡す主要PID読取状態です。
    let liveTelemetryState: LiveTelemetryState

    /// 接続履歴画面へ渡す現在の履歴状態です。
    let connectionHistoryState: ConnectionHistoryState

    /// HOMEの操作をAppShellへ通知するクロージャです。
    let sendHomeAction: (IOSHomeAction) -> Void

    /// 設定画面の操作をAppShellへ通知するクロージャです。
    let sendSettingsAction: (IOSSettingsAction) -> Void

    /// アカウント同期対象の設定操作を通知するクロージャです。
    let sendAccountSettingsAction: (AccountSettingsAction) -> Void

    /// 車両登録・編集操作をVehicleManagementへ通知します。
    let sendVehicleManagementAction: (VehicleManagementAction) -> Void

    /// 主要PID読取操作をLiveTelemetryへ通知します。
    let sendLiveTelemetryAction: (LiveTelemetryAction) -> Void

    /// 接続履歴操作をLogHistoryへ通知します。
    let sendConnectionHistoryAction: (ConnectionHistoryAction) -> Void

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
        if destination == .home {
            if [.identifying, .confirmingIdentification, .registering, .failed].contains(vehicleManagementState.phase) {
                IOSVehicleRegistrationView(
                    state: vehicleManagementState,
                    send: sendVehicleManagementAction
                )
            } else {
                IOSHomeView(
                    state: IOSHomeState(
                        settingsState: settingsState,
                        liveTelemetryState: liveTelemetryState
                    ),
                    send: sendHomeAction
                )
            }
        } else if destination == .liveLog {
            IOSLiveTelemetryView(
                state: liveTelemetryState,
                send: sendLiveTelemetryAction
            )
        } else if destination == .history {
            IOSConnectionHistoryView(
                state: connectionHistoryState,
                send: sendConnectionHistoryAction
            )
        } else if destination == .garage {
            IOSGarageView(state: vehicleManagementState, send: sendVehicleManagementAction)
        } else if destination == .settings {
            IOSSettingsView(
                state: settingsState,
                accountSettings: accountSettings,
                send: sendSettingsAction,
                sendAccountSettingsAction: sendAccountSettingsAction,
                accountDeletionPhase: accountDeletionPhase,
                accountDeletionFailure: accountDeletionFailure,
                sendAuthenticationAction: sendAuthenticationAction
            )
        } else {
            placeholder
        }
    }

    /// 未実装の遷移先を識別できるモバイル向けプレースホルダーです。
    private var placeholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                brandHeader

                VStack(alignment: .leading, spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))

                        Image(systemName: destination.systemImage)
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(.tint)
                    }
                    .frame(width: 82, height: 82)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(destination.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))

                        Text(destination.subtitle)
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("shell.destination.placeholder")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("ios-destination-\(destination.rawValue)")
    }

    /// 製品名とモバイル向けコンセプトを示すコンパクトなブランド表示です。
    private var brandHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.58)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.accentColor.opacity(0.28), radius: 12, y: 5)

                Image(systemName: "car.side.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("Project ZD8")
                    .font(.system(.headline, design: .rounded, weight: .bold))

                Text("ios.shell.tagline")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
