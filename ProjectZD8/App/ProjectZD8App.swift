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

    /// 「エンジン停止とみなす時間」の設定を保持するモデルです。
    @State private var vehicleOffDelayModel: VehicleOffDetectionDelayModel

    #if os(iOS)
    /// iOS設定画面へ注入するプレゼンテーションモデルです。
    @State private var iOSSettingsModel: IOSSettingsPresentationModel

    /// 自動記録設定と記録開始方法の選択画面の状態を保持するモデルです。
    @State private var automaticRecordingModel: AutomaticRecordingPreferenceModel

    /// 未登録車両の警告を保持するモデルです。
    @State private var unassignedVINWarningModel: UnassignedObservedVINWarningModel

    /// 車両を特定できなかったログの警告と紐付けを保持するモデルです。
    @State private var vehicleUnknownSessionModel: VehicleUnknownSessionModel

    /// 起動・認証状態・既定アダプター設定・前面復帰を常駐リンク監視へ伝える型です。
    private let adapterLinkSupervision: IOSAdapterLinkSupervisionDriver

    /// PID継続取得の状態と前面復帰を記録中のLive Activityへ伝える型です。
    private let sessionActivity: IOSRecordingSessionActivityDriver
    #endif

    #if os(macOS)
    /// macOS設定画面へ注入するプレゼンテーションモデルです。
    @State private var macOSSettingsModel: MacOSSettingsPresentationModel
    #endif

    /// プラットフォーム固有の依存関係を組み立ててアプリを生成します。
    ///
    /// 責務: 現在のプラットフォーム用Compositionからアプリケーションルート依存関係を構築します。
    /// iOSでは画面の表示を待たずに常駐リンク監視を始めます。
    init() {
        #if os(iOS)
        let root = IOSApplicationRoot.make()
        let models = root.models
        #elseif os(macOS)
        let models = ApplicationRootAssembly.makeModels(MacOSApplicationComposition.self)
        #endif
        models.connectAccountDeletionDrain()
        _authenticationModel = State(initialValue: models.authentication)
        _vehicleOffDelayModel = State(initialValue: ApplicationRootAssembly.makeVehicleOffDetectionDelayModel())
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
        _automaticRecordingModel = State(initialValue: root.automaticRecording)
        _unassignedVINWarningModel = State(initialValue: root.unassignedVINWarning)
        _vehicleUnknownSessionModel = State(initialValue: root.vehicleUnknownSessions)
        adapterLinkSupervision = root.adapterLinkSupervision
        root.adapterLinkSupervision.launch()
        sessionActivity = root.sessionActivity
        root.sessionActivity.launch()
        #endif
    }

    /// 現在のプラットフォームが所有するルート画面をアプリケーションウインドウへ配置します。
    ///
    /// 責務: 現在のAppleプラットフォームを独立したAppShellへ結び付けます。
    var body: some Scene {
        WindowGroup {
            Group {
#if os(iOS)
                if authenticationModel.state.phase.showsAuthenticatedShell {
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
                        vehicleOffDelayModel: vehicleOffDelayModel,
                        unassignedVINWarningModel: unassignedVINWarningModel,
                        vehicleUnknownSessionModel: vehicleUnknownSessionModel,
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
                if authenticationModel.state.phase.showsAuthenticatedShell {
                    MacOSAppShellView(
                        accountSettingsModel: accountSettingsModel,
                        settingsModel: macOSSettingsModel,
                        vehicleManagementModel: vehicleManagementModel,
                        maintenanceModel: maintenanceModel,
                        liveTelemetryModel: liveTelemetryModel,
                        connectionHistoryModel: connectionHistoryModel,
                        sessionLogAnalysisModel: sessionLogAnalysisModel,
                        startVehicleConnection: startVehicleConnection,
                        vehicleOffDelayModel: vehicleOffDelayModel,
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
            .onChange(of: authenticationModel.state.phase) { previous, phase in
                handleAuthenticationPhaseChange(phase, previous: previous)
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

    /// バックグラウンド移行時に保存待ちの取得記録を保存させ、操作可能へ戻ったとき取得の一時停止へ復帰の機会を伝え、
    /// 認証へ前面復帰(確認できなかったサインインの再確認)を、iOSでは常駐リンク監視へ前面復帰・背面移行を、
    /// 記録中のLive Activityへ前面復帰を伝え、認証済みセッション概要と整備記録を再同期します。
    ///
    /// 責務: 1件のScene段階変更を取得記録のflush要求・取得ループの起床通知・前面復帰の通知、
    /// または認証済み接続履歴と整備記録の更新要求へ変換します。
    /// - Parameter phase: 現在のScene段階。
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .background {
            liveTelemetryModel.send(.backgroundTransitionOccurred)
            #if os(iOS)
            adapterLinkSupervision.appDidEnterBackground()
            #endif
        }
        guard phase == .active else { return }
        liveTelemetryModel.send(.foregroundTransitionOccurred)
        authenticationModel.send(.foregroundEntered)
        #if os(iOS)
        adapterLinkSupervision.appDidBecomeActive()
        sessionActivity.appDidBecomeActive()
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
        vehicleUnknownSessionModel.send(
            .accountIdentifierChanged(authenticationModel.state.session?.userIdentifier)
        )
        #endif
    }

    /// 認証段階の変化に応じて、各機能のアカウントスコープと端末内表示状態を切り替えます。
    ///
    /// 責務: 認証段階の変化をアカウントスコープの解除・復元とプラットフォーム設定状態の再生成へ反映します。
    /// 進行中の取得は `AuthenticationAcquisitionEndPolicy` が決めた理由(サインアウトとアカウント削除の開始なら `accountSignedOut`)で終えます。
    /// アカウント削除の開始(`deletingAccount`)では各機能のスコープを外して同期・保存・自動アップロード・自動記録を止め、
    /// 削除が失敗して認証済みへ戻ったときはスコープを復元します。
    /// - Parameters:
    ///   - phase: Authenticationが確定した新しい認証段階。
    ///   - previous: 変化前の認証段階。
    private func handleAuthenticationPhaseChange(_ phase: AuthenticationPhase, previous: AuthenticationPhase) {
        if let reason = AuthenticationAcquisitionEndPolicy().endReason(forChangeTo: phase) {
            liveTelemetryModel.send(.endRequested(reason))
        }
        switch phase {
        case .signedIn:
            if previous == .deletingAccount { activateAuthenticatedSettingsScope() }
            #if os(iOS)
            automaticRecordingModel.send(.signInStateChanged(isSignedIn: true))
            #endif
        case .deletingAccount:
            detachAccountScope()
        case .signedOut:
            detachAccountScope()
            resetPlatformSettingsModel()
        case .checkingSession, .signingIn:
            break
        }
    }

    /// 全機能のアカウントスコープを外します。
    ///
    /// 責務: 同期・保存・自動アップロード・自動記録が現在のアカウントへ作用しない状態にします。
    private func detachAccountScope() {
        connectionSessionLifecycleModel.send(.accountIdentifierChanged(nil))
        connectionHistoryModel.send(.accountIdentifierChanged(nil))
        accountSettingsModel.send(.accountIdentifierChanged(nil))
        vehicleManagementModel.send(.accountIdentifierChanged(nil))
        maintenanceModel.send(.accountIdentifierChanged(nil))
        #if os(iOS)
        automaticRecordingModel.send(.signInStateChanged(isSignedIn: false))
        unassignedVINWarningModel.send(.accountIdentifierChanged(nil))
        vehicleUnknownSessionModel.send(.accountIdentifierChanged(nil))
        #endif
    }

    /// ログアウトで端末内の設定画面状態を初期化します。
    ///
    /// 責務: プラットフォーム別の設定プレゼンテーションモデルを作り直します。
    private func resetPlatformSettingsModel() {
        #if os(iOS)
        iOSSettingsModel = IOSApplicationComposition.makeSettingsPresentationModel()
        #elseif os(macOS)
        macOSSettingsModel = MacOSApplicationComposition.makeSettingsPresentationModel()
        #endif
    }
}
