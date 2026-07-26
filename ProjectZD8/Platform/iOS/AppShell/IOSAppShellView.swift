#if os(iOS)
import SwiftUI

/// iOSアプリケーション専用のルートレイアウトを描画します。
struct IOSAppShellView: View {
    /// iOSシェルが現在表示している遷移先です。
    @State private var selectedDestination: IOSAppShellDestination = .home

    /// Connectionを除くアカウント同期対象設定を提供するモデルです。
    let accountSettingsModel: AccountSettingsModel

    /// Bluetoothアダプター選択状態を画面操作へ変換するモデルです。
    let settingsModel: IOSSettingsPresentationModel

    /// 車両一覧、登録、同期状態を提供するモデルです。
    let vehicleManagementModel: VehicleManagementModel

    /// 車両別整備一覧、編集、同期状態を提供するモデルです。
    let maintenanceModel: MaintenanceModel

    /// 主要PIDの読取状態を提供するモデルです。
    let liveTelemetryModel: LiveTelemetryModel

    /// 接続セッション履歴を提供するモデルです。
    let connectionHistoryModel: ConnectionHistoryModel

    /// 保存済みPID時系列解析を提供するモデルです。
    let sessionLogAnalysisModel: SessionLogAnalysisModel

    /// HOME接続要求をApplicationワークフローへ通知するユースケースです。
    let startVehicleConnection: StartVehicleConnectionUseCase

    /// Authenticationが管理するアカウント削除の現在段階です。
    let accountDeletionPhase: AccountDeletionPhase

    /// Authenticationが保持する直近のアカウント削除失敗です。
    let accountDeletionFailure: AccountDeletionFailure?

    /// アカウント削除の型付き操作をAuthenticationへ通知します。
    let sendAuthenticationAction: (AuthenticationAction) -> Void

    /// アカウント設定モデルとConnection設定モデルを注入してiOSルート画面を生成します。
    ///
    /// 責務: iOS AppShellを同期設定、Connection設定、車両管理の独立したモデルへ結び付けます。
    /// - Parameters:
    ///   - accountSettingsModel: 言語と外観を提供するアカウント設定モデル。
    ///   - settingsModel: Bluetooth候補選択状態を提供するモデル。
    ///   - vehicleManagementModel: 登録車両とVIN確認状態を提供するモデル。
    ///   - maintenanceModel: 車両別の整備一覧、編集、同期状態を提供するモデル。
    ///   - liveTelemetryModel: 主要PID読取状態を提供するモデル。
    ///   - connectionHistoryModel: アカウント単位の接続履歴を提供するモデル。
    ///   - sessionLogAnalysisModel: 保存済みPID時系列解析を提供するモデル。
    ///   - startVehicleConnection: HOME接続要求を車両識別とPID取得へ展開するユースケース。
    ///   - accountDeletionPhase: アカウント削除の現在段階。
    ///   - accountDeletionFailure: 直近のアカウント削除失敗。
    ///   - sendAuthenticationAction: アカウント削除操作の通知先。
    init(
        accountSettingsModel: AccountSettingsModel,
        settingsModel: IOSSettingsPresentationModel,
        vehicleManagementModel: VehicleManagementModel,
        maintenanceModel: MaintenanceModel,
        liveTelemetryModel: LiveTelemetryModel,
        connectionHistoryModel: ConnectionHistoryModel,
        sessionLogAnalysisModel: SessionLogAnalysisModel,
        startVehicleConnection: StartVehicleConnectionUseCase,
        accountDeletionPhase: AccountDeletionPhase,
        accountDeletionFailure: AccountDeletionFailure?,
        sendAuthenticationAction: @escaping (AuthenticationAction) -> Void
    ) {
        self.accountSettingsModel = accountSettingsModel
        self.settingsModel = settingsModel
        self.vehicleManagementModel = vehicleManagementModel
        self.maintenanceModel = maintenanceModel
        self.liveTelemetryModel = liveTelemetryModel
        self.connectionHistoryModel = connectionHistoryModel
        self.sessionLogAnalysisModel = sessionLogAnalysisModel
        self.startVehicleConnection = startVehicleConnection
        self.accountDeletionPhase = accountDeletionPhase
        self.accountDeletionFailure = accountDeletionFailure
        self.sendAuthenticationAction = sendAuthenticationAction
    }

    /// iPhone向けのコンテンツ領域と下部ナビゲーションを提供します。
    ///
    /// 責務: 選択中の遷移先と表示設定を使ってiOS AppShellを描画します。
    var body: some View {
        appearanceAppliedContent
    }

    /// 選択した外観がシステム追従へ戻せる状態でiOSシェルへ適用された表示です。
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

    /// 言語と外観を適用する前のiOSシェル本体です。
    private var content: some View {
        ZStack {
            IOSAppShellBackground()

            IOSAppShellTabBar(selection: $selectedDestination) { destination in
                destinationContent(for: destination)
            }
        }
        .environment(\.locale, Locale(identifier: accountSettingsModel.settings.language.localeIdentifier))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-app-shell")
        .onChange(of: selectedDestination) { _, destination in
            handleDestinationSelection(destination)
        }
    }

    /// 指定されたタブに対応するiOS専用画面を生成します。
    ///
    /// 責務: 1件のAppShell遷移先を必要な表示状態と操作通知先へ接続します。
    /// - Parameter destination: 生成する画面を識別する遷移先。
    /// - Returns: 指定された遷移先に対応するiOS画面。
    private func destinationContent(for destination: IOSAppShellDestination) -> some View {
        IOSDestinationView(
            destination: destination,
            settingsState: settingsModel.state,
            accountSettings: accountSettingsModel.settings,
            vehicleManagementState: vehicleManagementModel.state,
            maintenanceState: maintenanceModel.state,
            liveTelemetryState: liveTelemetryModel.state,
            connectionHistoryState: connectionHistoryModel.state,
            sessionLogAnalysisState: sessionLogAnalysisModel.state,
            sendHomeAction: handleHomeAction,
            sendSettingsAction: settingsModel.send,
            sendAccountSettingsAction: accountSettingsModel.send,
            sendVehicleManagementAction: vehicleManagementModel.send,
            sendMaintenanceAction: maintenanceModel.send,
            sendLiveTelemetryAction: liveTelemetryModel.send,
            sendConnectionHistoryAction: connectionHistoryModel.send,
            sendSessionLogAnalysisAction: sessionLogAnalysisModel.send,
            accountDeletionPhase: accountDeletionPhase,
            accountDeletionFailure: accountDeletionFailure,
            sendAuthenticationAction: sendAuthenticationAction
        )
    }

    /// 選択された画面が必要とする最新表示を型付き操作で要求します。
    ///
    /// 責務: AppShellの遷移先変更を選択画面だけの更新要求へ変換します。
    /// - Parameter destination: ユーザーまたは画面操作が選択した遷移先。
    private func handleDestinationSelection(_ destination: IOSAppShellDestination) {
        switch destination {
        case .history:
            connectionHistoryModel.send(.refreshRequested)
        case .garage:
            vehicleManagementModel.send(.refreshRequested)
        case .home, .liveLog, .maintenance, .settings:
            break
        }
    }

    /// HOMEから受け取った1件の操作をiOSナビゲーションへ反映します。
    ///
    /// 責務: HOMEのアダプター設定要求を設定タブへの遷移と注目要求へ変換します。
    /// - Parameter action: HOMEから通知された型付き操作。
    private func handleHomeAction(_ action: IOSHomeAction) {
        switch action {
        case .adapterSetupRequested:
            selectedDestination = .settings
            settingsModel.send(.adapterAttentionRequested)
        case let .vehicleConnectionRequested(endpoint):
            startVehicleConnection.execute(endpoint: endpoint)
        case .vehicleDisconnectionRequested:
            liveTelemetryModel.send(.stopRequested)
        }
    }
}
#endif
