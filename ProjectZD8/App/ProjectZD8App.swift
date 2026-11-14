import SwiftUI

/// ProjectZD8のプロセスエントリーポイントとプラットフォーム別ルート画面を構築します。
@main
struct ProjectZD8App: App {
    /// ウインドウが再び操作可能になったことを同期開始へ利用するScene状態です。
    @Environment(\.scenePhase) private var scenePhase

    /// ルート画面の表示可否を決定する認証セッションモデルです。
    @State private var authenticationModel: AuthenticationSessionModel

    /// Connectionを除く設定をアカウント単位で保持するモデルです。
    @State private var accountSettingsModel: AccountSettingsModel

    /// 登録車両、VIN確認、CloudKit同期を保持するモデルです。
    @State private var vehicleManagementModel: VehicleManagementModel

    /// 車両別の軽整備・重整備とCloudKit同期を保持するモデルです。
    @State private var maintenanceModel: MaintenanceModel

    /// 主要PIDの1回読取り状態を保持するモデルです。
    @State private var liveTelemetryModel: LiveTelemetryModel

    /// 接続セッションの開始、車両関連付け、終了を保持するモデルです。
    @State private var connectionSessionLifecycleModel: ConnectionSessionLifecycleModel

    /// アカウント単位の接続履歴を保持するモデルです。
    @State private var connectionHistoryModel: ConnectionHistoryModel

    /// 保存済みPIDログの読取専用解析状態を保持するモデルです。
    @State private var sessionLogAnalysisModel: SessionLogAnalysisModel

    /// HOME接続要求を車両識別とPID継続取得へ展開するユースケースです。
    private let startVehicleConnection: StartVehicleConnectionUseCase

    #if os(iOS)
    /// iOS設定画面へ注入するプレゼンテーションモデルです。
    @State private var iOSSettingsModel: IOSSettingsPresentationModel

    /// 通知で了承された接続要求を認証完了まで保持するバッファーです。
    @State private var promptedVehicleConnectionRequest: PromptedVehicleConnectionRequestBuffer

    /// 既定BLE到来をユーザー承認付き接続要求へ変換するユースケースです。
    private let promptForDefaultAdapterConnection: PromptForDefaultAdapterConnectionUseCase
    #endif

    #if os(macOS)
    /// macOS設定画面へ注入するプレゼンテーションモデルです。
    @State private var macOSSettingsModel: MacOSSettingsPresentationModel
    #endif

    /// プラットフォーム固有の依存関係を組み立ててアプリを生成します。
    ///
    /// 責務: 現在のプラットフォーム用Compositionからアプリケーションルート依存関係を構築します。
    init() {
        #if os(iOS)
        let models = ApplicationRootAssembly.makeModels(IOSApplicationComposition.self)
        #elseif os(macOS)
        let models = ApplicationRootAssembly.makeModels(MacOSApplicationComposition.self)
        #endif
        _authenticationModel = State(initialValue: models.authentication)
        _accountSettingsModel = State(initialValue: models.accountSettings)
        #if os(iOS)
        _iOSSettingsModel = State(initialValue: IOSApplicationComposition.makeSettingsPresentationModel())
        #elseif os(macOS)
        _macOSSettingsModel = State(initialValue: MacOSApplicationComposition.makeSettingsPresentationModel())
        #endif
        _vehicleManagementModel = State(initialValue: models.vehicleManagement)
        _maintenanceModel = State(initialValue: models.maintenance)
        _liveTelemetryModel = State(initialValue: models.liveTelemetry)
        _connectionSessionLifecycleModel = State(initialValue: models.connectionSessionLifecycle)
        _connectionHistoryModel = State(initialValue: models.connectionHistory)
        _sessionLogAnalysisModel = State(initialValue: models.sessionLogAnalysis)
        startVehicleConnection = ApplicationRootAssembly.makeStartVehicleConnection(vehicleManagement: models.vehicleManagement)
        #if os(iOS)
        let promptedVehicleConnectionRequest = PromptedVehicleConnectionRequestBuffer()
        _promptedVehicleConnectionRequest = State(initialValue: promptedVehicleConnectionRequest)
        promptForDefaultAdapterConnection =
            IOSApplicationComposition.makeDefaultAdapterConnectionPromptUseCase {
                promptedVehicleConnectionRequest.store($0)
            }
        #endif
    }

    /// 現在のプラットフォームが所有するルート画面をアプリケーションウインドウへ配置します。
    ///
    /// 責務: 現在のAppleプラットフォームを独立したAppShellへ結び付けます。
    var body: some Scene {
        WindowGroup {
            Group {
#if os(iOS)
                if authenticationModel.state.phase == .signedIn {
                    IOSAppShellView(
                        accountSettingsModel: accountSettingsModel,
                        settingsModel: iOSSettingsModel,
                        vehicleManagementModel: vehicleManagementModel,
                        maintenanceModel: maintenanceModel,
                        liveTelemetryModel: liveTelemetryModel,
                        connectionHistoryModel: connectionHistoryModel,
                        sessionLogAnalysisModel: sessionLogAnalysisModel,
                        startVehicleConnection: startVehicleConnection,
                        accountDeletionPhase: authenticationModel.state.accountDeletionPhase,
                        accountDeletionFailure: authenticationModel.state.accountDeletionFailure,
                        sendAuthenticationAction: authenticationModel.send
                    )
                    .transition(.opacity)
                    .onAppear(perform: activateAuthenticatedSettingsScope)
                } else {
                    IOSLoginView(
                        state: authenticationModel.state,
                        send: authenticationModel.send
                    )
                    .transition(.opacity)
                }
#elseif os(macOS)
                if authenticationModel.state.phase == .signedIn {
                    MacOSAppShellView(
                        accountSettingsModel: accountSettingsModel,
                        settingsModel: macOSSettingsModel,
                        vehicleManagementModel: vehicleManagementModel,
                        maintenanceModel: maintenanceModel,
                        liveTelemetryModel: liveTelemetryModel,
                        connectionHistoryModel: connectionHistoryModel,
                        sessionLogAnalysisModel: sessionLogAnalysisModel,
                        startVehicleConnection: startVehicleConnection,
                        accountDeletionPhase: authenticationModel.state.accountDeletionPhase,
                        accountDeletionFailure: authenticationModel.state.accountDeletionFailure,
                        sendAuthenticationAction: authenticationModel.send
                    )
                    .transition(.opacity)
                    .onAppear(perform: activateAuthenticatedSettingsScope)
                } else {
                    MacOSLoginView(
                        state: authenticationModel.state,
                        send: authenticationModel.send
                    )
                    .transition(.opacity)
                }
#endif
            }
            .onChange(of: authenticationModel.state.phase) { _, phase in
                handleAuthenticationPhaseChange(phase)
            }
            .onChange(of: scenePhase) { _, phase in
                handleScenePhaseChange(phase)
            }
            .onChange(of: accountSettingsModel.settings.automaticSessionUploadEnabled) { _, isEnabled in
                connectionSessionLifecycleModel.send(.automaticUploadChanged(isEnabled))
                connectionHistoryModel.send(.automaticUploadChanged(isEnabled))
            }
            .onChange(of: vehicleManagementModel.state.vehicles) { _, vehicles in
                maintenanceModel.send(.vehiclesChanged(vehicles))
            }
            #if os(iOS)
            .onChange(of: iOSSettingsModel.state.defaultAdapterPreference) { _, _ in
                refreshDefaultAdapterArrivalMonitoring()
            }
            .onChange(of: promptedVehicleConnectionRequest.pendingEndpoint) { _, _ in
                consumePromptedVehicleConnectionIfPossible()
            }
            #endif
        }
    }

    /// バックグラウンド移行時に保存待ちの取得記録を保存させ、操作可能へ戻ったとき取得の一時停止へ復帰の機会を伝え、
    /// 認証済みセッション概要と整備記録を再同期します。
    ///
    /// 責務: 1件のScene段階変更を取得記録のflush要求・取得ループの起床通知、または認証済み接続履歴と整備記録の更新要求へ変換します。
    /// - Parameter phase: 現在のScene段階。
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .background { liveTelemetryModel.send(.backgroundTransitionOccurred) }
        if phase == .active { liveTelemetryModel.send(.foregroundTransitionOccurred) }
        guard phase == .active, authenticationModel.state.phase == .signedIn else { return }
        connectionHistoryModel.send(.refreshRequested)
        maintenanceModel.send(.refreshRequested)
        #if os(iOS)
        consumePromptedVehicleConnectionIfPossible()
        #endif
    }

    /// 認証済みAppleユーザーを設定、車両、整備、接続履歴の保存スコープへ反映します。
    ///
    /// 責務: 現在の認証セッション識別子を各アカウントスコープ付き機能へ通知します。
    private func activateAuthenticatedSettingsScope() {
        accountSettingsModel.send(
            .accountIdentifierChanged(authenticationModel.state.session?.userIdentifier)
        )
        connectionSessionLifecycleModel.send(
            .automaticUploadChanged(accountSettingsModel.settings.automaticSessionUploadEnabled)
        )
        vehicleManagementModel.send(
            .accountIdentifierChanged(authenticationModel.state.session?.userIdentifier)
        )
        maintenanceModel.send(
            .vehiclesChanged(vehicleManagementModel.state.vehicles)
        )
        maintenanceModel.send(
            .accountIdentifierChanged(authenticationModel.state.session?.userIdentifier)
        )
        connectionSessionLifecycleModel.send(
            .accountIdentifierChanged(authenticationModel.state.session?.userIdentifier)
        )
        connectionHistoryModel.send(
            .accountIdentifierChanged(authenticationModel.state.session?.userIdentifier)
        )
        connectionHistoryModel.send(
            .automaticUploadChanged(accountSettingsModel.settings.automaticSessionUploadEnabled)
        )
        #if os(iOS)
        refreshDefaultAdapterArrivalMonitoring()
        consumePromptedVehicleConnectionIfPossible()
        #endif
    }

    /// ログアウト状態へ変わったときに設定スコープと端末内表示状態を初期化します。
    ///
    /// 責務: 認証段階の変化をアカウント設定監視解除とプラットフォーム設定状態の再生成へ反映します。
    /// - Parameter phase: Authenticationが確定した新しい認証段階。
    private func handleAuthenticationPhaseChange(_ phase: AuthenticationPhase) {
        if phase == .signedIn {
            #if os(iOS)
            refreshDefaultAdapterArrivalMonitoring()
            consumePromptedVehicleConnectionIfPossible()
            #endif
            return
        }
        guard phase == .signedOut else { return }
        liveTelemetryModel.send(.stopRequested)
        connectionSessionLifecycleModel.send(.accountIdentifierChanged(nil))
        connectionHistoryModel.send(.accountIdentifierChanged(nil))
        accountSettingsModel.send(.accountIdentifierChanged(nil))
        vehicleManagementModel.send(.accountIdentifierChanged(nil))
        maintenanceModel.send(.accountIdentifierChanged(nil))
        #if os(iOS)
        promptForDefaultAdapterConnection.stop()
        iOSSettingsModel = IOSApplicationComposition.makeSettingsPresentationModel()
        #elseif os(macOS)
        macOSSettingsModel = MacOSApplicationComposition.makeSettingsPresentationModel()
        #endif
    }

    #if os(iOS)
    /// 現在の認証状態に合わせて既定BLE到来監視を開始または停止します。
    ///
    /// 責務: 認証済み状態だけを既定BLE接続確認ユースケースの有効期間へ変換します。
    private func refreshDefaultAdapterArrivalMonitoring() {
        if authenticationModel.state.phase == .signedIn {
            promptForDefaultAdapterConnection.start()
        } else {
            promptForDefaultAdapterConnection.stop()
        }
    }

    /// 認証済みの場合に通知で了承された接続要求を既存接続フローへ渡します。
    ///
    /// 責務: 1件の保留中接続了承を認証済みHOME接続ユースケースへ引き渡します。
    private func consumePromptedVehicleConnectionIfPossible() {
        guard authenticationModel.state.phase == .signedIn,
              let endpoint = promptedVehicleConnectionRequest.consume() else {
            return
        }
        startVehicleConnection.execute(endpoint: endpoint)
    }
    #endif
}
