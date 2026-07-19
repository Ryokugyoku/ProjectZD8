#if os(macOS)
import SwiftUI

/// macOSアプリケーション専用のルートレイアウトを描画します。
struct MacOSAppShellView: View {
    /// macOSシェルが現在表示している遷移先です。
    @State private var selectedDestination: MacOSSidebarDestination = .home

    /// Connectionを除くアカウント同期対象設定を提供するモデルです。
    let accountSettingsModel: AccountSettingsModel

    /// アダプター選択状態を画面操作へ変換するモデルです。
    let settingsModel: MacOSSettingsPresentationModel

    /// 車両一覧、登録、同期状態を提供するモデルです。
    let vehicleManagementModel: VehicleManagementModel

    /// 主要PIDの読取状態を提供するモデルです。
    let liveTelemetryModel: LiveTelemetryModel

    /// HOME接続要求をApplicationワークフローへ通知するユースケースです。
    let startVehicleConnection: StartVehicleConnectionUseCase

    /// Authenticationが管理するアカウント削除の現在段階です。
    let accountDeletionPhase: AccountDeletionPhase

    /// Authenticationが保持する直近のアカウント削除失敗です。
    let accountDeletionFailure: AccountDeletionFailure?

    /// アカウント削除の型付き操作をAuthenticationへ通知します。
    let sendAuthenticationAction: (AuthenticationAction) -> Void

    /// アカウント設定モデルとConnection設定モデルを注入してmacOSルート画面を生成します。
    ///
    /// 責務: macOS AppShellを同期設定、Connection設定、車両管理の独立したモデルへ結び付けます。
    /// - Parameters:
    ///   - accountSettingsModel: 言語と外観を提供するアカウント設定モデル。
    ///   - settingsModel: アダプター選択状態を提供するモデル。
    ///   - vehicleManagementModel: 登録車両とVIN確認状態を提供するモデル。
    ///   - liveTelemetryModel: 主要PID読取状態を提供するモデル。
    ///   - startVehicleConnection: HOME接続要求を車両識別とPID取得へ展開するユースケース。
    ///   - accountDeletionPhase: アカウント削除の現在段階。
    ///   - accountDeletionFailure: 直近のアカウント削除失敗。
    ///   - sendAuthenticationAction: アカウント削除操作の通知先。
    init(
        accountSettingsModel: AccountSettingsModel,
        settingsModel: MacOSSettingsPresentationModel,
        vehicleManagementModel: VehicleManagementModel,
        liveTelemetryModel: LiveTelemetryModel,
        startVehicleConnection: StartVehicleConnectionUseCase,
        accountDeletionPhase: AccountDeletionPhase,
        accountDeletionFailure: AccountDeletionFailure?,
        sendAuthenticationAction: @escaping (AuthenticationAction) -> Void
    ) {
        self.accountSettingsModel = accountSettingsModel
        self.settingsModel = settingsModel
        self.vehicleManagementModel = vehicleManagementModel
        self.liveTelemetryModel = liveTelemetryModel
        self.startVehicleConnection = startVehicleConnection
        self.accountDeletionPhase = accountDeletionPhase
        self.accountDeletionFailure = accountDeletionFailure
        self.sendAuthenticationAction = sendAuthenticationAction
    }

    /// アプリケーション状態やインフラ状態を所有しないレスポンシブなmacOSシェルを提供します。
    ///
    /// 責務: 現在のウインドウ寸法と選択中の遷移先を使ってmacOS AppShellを描画します。
    var body: some View {
        appearanceAppliedContent
    }

    /// 選択した外観がシステム追従へ戻せる状態でmacOSシェルへ適用された表示です。
    @ViewBuilder
    private var appearanceAppliedContent: some View {
        switch accountSettingsModel.settings.appearance {
        case .system:
            content
        case .light:
            content.preferredColorScheme(.light)
        case .dark:
            content.preferredColorScheme(.dark)
        }
    }

    /// 言語と外観を適用する前のmacOSシェル本体です。
    private var content: some View {
        GeometryReader { proxy in
            let metrics = MacOSAppShellMetrics.resolve(for: proxy.size)

            HStack(spacing: 0) {
                MacOSSidebarView(
                    selection: $selectedDestination,
                    metrics: metrics
                )

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)

                MacOSDestinationView(
                    destination: selectedDestination,
                    metrics: metrics,
                    settingsState: settingsModel.state,
                    accountSettings: accountSettingsModel.settings,
                    vehicleManagementState: vehicleManagementModel.state,
                    liveTelemetryState: liveTelemetryModel.state,
                    sendHomeAction: handleHomeAction,
                    sendSettingsAction: settingsModel.send,
                    sendAccountSettingsAction: accountSettingsModel.send,
                    sendVehicleManagementAction: vehicleManagementModel.send,
                    sendLiveTelemetryAction: liveTelemetryModel.send,
                    accountDeletionPhase: accountDeletionPhase,
                    accountDeletionFailure: accountDeletionFailure,
                    sendAuthenticationAction: sendAuthenticationAction
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-app-shell")
        .frame(minWidth: 640, minHeight: 420)
        .environment(\.locale, Locale(identifier: accountSettingsModel.settings.language.localeIdentifier))
    }

    /// HOMEから受け取った1件の操作をmacOSナビゲーションへ反映します。
    ///
    /// 責務: HOMEのアダプター設定要求を設定画面への遷移と注目要求へ変換します。
    /// - Parameter action: HOMEから通知された型付き操作。
    private func handleHomeAction(_ action: MacOSHomeAction) {
        switch action {
        case .adapterSetupRequested:
            selectedDestination = .settings
            settingsModel.send(.adapterAttentionRequested)
        case let .vehicleConnectionRequested(endpoint):
            selectedDestination = .garage
            startVehicleConnection.execute(endpoint: endpoint)
        }
    }
}
#endif
