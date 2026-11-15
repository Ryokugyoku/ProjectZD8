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

    /// 自動記録設定と記録開始方法の選択画面の状態を保持するモデルです。
    @State private var automaticRecordingModel: AutomaticRecordingPreferenceModel

    /// 未登録車両の警告を保持するモデルです。
    @State private var unassignedVINWarningModel: UnassignedObservedVINWarningModel

    /// 起動・認証状態・既定アダプター設定・前面復帰を常駐リンク監視へ伝える型です。
    private let adapterLinkSupervision: IOSAdapterLinkSupervisionDriver
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
        let root = IOSApplicationRoot.make()
        _authenticationModel = State(initialValue: root.authenticationModel)
        _accountSettingsModel = State(initialValue: root.accountSettingsModel)
        _iOSSettingsModel = State(initialValue: root.settingsModel)
        _automaticRecordingModel = State(initialValue: root.automaticRecordingModel)
        _unassignedVINWarningModel = State(initialValue: root.unassignedVINWarningModel)
        _vehicleManagementModel = State(initialValue: root.vehicleManagementModel)
        _maintenanceModel = State(initialValue: root.maintenanceModel)
        _liveTelemetryModel = State(initialValue: root.liveTelemetryModel)
        _connectionSessionLifecycleModel = State(initialValue: root.connectionSessionLifecycleModel)
        _connectionHistoryModel = State(initialValue: root.connectionHistoryModel)
        _sessionLogAnalysisModel = State(initialValue: root.sessionLogAnalysisModel)
        startVehicleConnection = root.startVehicleConnection
        adapterLinkSupervision = root.adapterLinkSupervision
        root.adapterLinkSupervision.launch()
        #endif

        #if os(macOS)
        let root = MacOSApplicationRoot.make()
        _authenticationModel = State(initialValue: root.authenticationModel)
        _accountSettingsModel = State(initialValue: root.accountSettingsModel)
        _macOSSettingsModel = State(initialValue: root.settingsModel)
        _vehicleManagementModel = State(initialValue: root.vehicleManagementModel)
        _maintenanceModel = State(initialValue: root.maintenanceModel)
        _liveTelemetryModel = State(initialValue: root.liveTelemetryModel)
        _connectionSessionLifecycleModel = State(initialValue: root.connectionSessionLifecycleModel)
        _connectionHistoryModel = State(initialValue: root.connectionHistoryModel)
        _sessionLogAnalysisModel = State(initialValue: root.sessionLogAnalysisModel)
        startVehicleConnection = root.startVehicleConnection
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
                        automaticRecordingModel: automaticRecordingModel,
                        unassignedVINWarningModel: unassignedVINWarningModel,
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
                adapterLinkSupervision.defaultAdapterPreferenceDidChange()
            }
            #endif
        }
    }

    /// アプリが操作可能へ戻ったとき常駐リンク監視へ伝え、認証済みセッション概要と整備記録を再同期します。
    ///
    /// 責務: 1件のScene段階変更を前面復帰の通知と、認証済み接続履歴と整備記録の更新要求へ変換します。
    /// - Parameter phase: 現在のScene段階。
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else { return }
        #if os(iOS)
        adapterLinkSupervision.appDidBecomeActive()
        #endif
        guard authenticationModel.state.phase == .signedIn else { return }
        connectionHistoryModel.send(.refreshRequested)
        maintenanceModel.send(.refreshRequested)
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
        automaticRecordingModel.send(.signInStateChanged(isSignedIn: authenticationModel.state.phase == .signedIn))
        unassignedVINWarningModel.send(
            .accountIdentifierChanged(authenticationModel.state.session?.userIdentifier)
        )
        #endif
    }

    /// ログアウト状態へ変わったときに設定スコープと端末内表示状態を初期化します。
    ///
    /// 責務: 認証段階の変化をアカウント設定監視解除とプラットフォーム設定状態の再生成へ反映します。
    /// - Parameter phase: Authenticationが確定した新しい認証段階。
    private func handleAuthenticationPhaseChange(_ phase: AuthenticationPhase) {
        if phase == .signedIn {
            #if os(iOS)
            automaticRecordingModel.send(.signInStateChanged(isSignedIn: true))
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
        automaticRecordingModel.send(.signInStateChanged(isSignedIn: false))
        unassignedVINWarningModel.send(.accountIdentifierChanged(nil))
        iOSSettingsModel = IOSApplicationComposition.makeSettingsPresentationModel()
        #elseif os(macOS)
        macOSSettingsModel = MacOSApplicationComposition.makeSettingsPresentationModel()
        #endif
    }
}
