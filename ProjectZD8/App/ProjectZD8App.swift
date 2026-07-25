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
        let connectionSessionRepository = IOSApplicationComposition.makeConnectionSessionRepository()
        let connectionSessionSynchronization = IOSApplicationComposition.makeConnectionSessionSynchronization(
            storage: connectionSessionRepository
        )
        let connectionHistoryModel = ConnectionHistoryModel(
            repository: connectionSessionRepository,
            synchronizeSessions: connectionSessionSynchronization,
            releaseRawCache: ReleaseConnectionSessionRawCacheUseCase(
                repository: connectionSessionRepository
            ),
            deleteSessionEverywhere: DeleteConnectionSessionEverywhereUseCase(
                localRepository: connectionSessionRepository,
                transferRepository: CloudKitConnectionSessionTransferRepository()
            ),
            reviewInterruptedSession: ReviewInterruptedConnectionSessionUseCase(
                repository: connectionSessionRepository
            ),
            evictStaleRawLogs: EvictStaleConnectionSessionRawLogsUseCase(
                sessionRepository: connectionSessionRepository,
                rawLogRepository: connectionSessionRepository
            )
        )
        let sessionLogAnalysisModel = SessionLogAnalysisModel(
            state: .init(),
            decodeTimeline: DecodeSessionLogTimelineUseCase(
                rawLogRepository: connectionSessionRepository,
                definitionRepository: IOSApplicationComposition.makeOBDPIDDefinitionRepository()
            ),
            prepareRawLog: PrepareConnectionSessionRawLogUseCase(
                sessionRepository: connectionSessionRepository,
                rawLogRepository: connectionSessionRepository,
                transferRepository: CloudKitConnectionSessionTransferRepository()
            )
        )
        let connectionSessionLifecycleModel = ConnectionSessionLifecycleModel(
            repository: connectionSessionRepository,
            rawLogRepository: connectionSessionRepository,
            acquisitionDevice: IOSApplicationComposition.makeConnectionSessionAcquisitionDevice(),
            historyDidChange: { connectionHistoryModel.send(.localDataChanged) },
            endedSessionUploadRequested: { session in
                connectionHistoryModel.send(.sessionUploadRequested(session.id))
            }
        )
        let liveTelemetryModel = IOSApplicationComposition.makeLiveTelemetryModel(
            sessionDidEnd: { connectionSessionLifecycleModel.send(.endRequested($0)) },
            distanceDidChange: { connectionSessionLifecycleModel.send(.distanceObserved($0)) },
            rawResponseDidReceive: { observation in
                try await MainActor.run {
                    try connectionSessionLifecycleModel.recordRawResponse(observation)
                }
            }
        )
        let vehicleManagementModel = IOSApplicationComposition.makeVehicleManagementModel(
            connectionSessionRepository: connectionSessionRepository,
            vehicleSessionsDidDelete: { connectionHistoryModel.send(.refreshRequested) }
        ) { vehicle, endpoint, identification in
            connectionSessionLifecycleModel.send(.startRequested)
            connectionSessionLifecycleModel.send(.vehicleResolved(vehicle))
            let mode: LiveTelemetryAcquisitionMode = ZD8VehicleModelPolicy().matches(identification.vin)
                || ZD8VehicleModelPolicy().matches(identification.obdIdentifier)
                ? .brzBetaPeriodic
                : .standardPolling
            liveTelemetryModel.send(.startRequested(endpoint, vehicle.id, mode))
        }
        _authenticationModel = State(
            initialValue: IOSApplicationComposition.makeAuthenticationSessionModel(
                connectionSessionStorage: connectionSessionRepository
            )
        )
        _accountSettingsModel = State(
            initialValue: IOSApplicationComposition.makeAccountSettingsModel()
        )
        _iOSSettingsModel = State(
            initialValue: IOSApplicationComposition.makeSettingsPresentationModel()
        )
        _vehicleManagementModel = State(
            initialValue: vehicleManagementModel
        )
        _liveTelemetryModel = State(
            initialValue: liveTelemetryModel
        )
        _connectionSessionLifecycleModel = State(initialValue: connectionSessionLifecycleModel)
        _connectionHistoryModel = State(initialValue: connectionHistoryModel)
        _sessionLogAnalysisModel = State(initialValue: sessionLogAnalysisModel)
        startVehicleConnection = StartVehicleConnectionUseCase(
            identifyVehicle: { vehicleManagementModel.send(.identifyRequested($0)) }
        )
        #endif

        #if os(macOS)
        let connectionSessionRepository = MacOSApplicationComposition.makeConnectionSessionRepository()
        let connectionSessionSynchronization = MacOSApplicationComposition.makeConnectionSessionSynchronization(
            storage: connectionSessionRepository
        )
        let connectionHistoryModel = ConnectionHistoryModel(
            repository: connectionSessionRepository,
            synchronizeSessions: connectionSessionSynchronization,
            releaseRawCache: ReleaseConnectionSessionRawCacheUseCase(
                repository: connectionSessionRepository
            ),
            deleteSessionEverywhere: DeleteConnectionSessionEverywhereUseCase(
                localRepository: connectionSessionRepository,
                transferRepository: CloudKitConnectionSessionTransferRepository()
            ),
            reviewInterruptedSession: ReviewInterruptedConnectionSessionUseCase(
                repository: connectionSessionRepository
            ),
            evictStaleRawLogs: EvictStaleConnectionSessionRawLogsUseCase(
                sessionRepository: connectionSessionRepository,
                rawLogRepository: connectionSessionRepository
            )
        )
        let sessionLogAnalysisModel = SessionLogAnalysisModel(
            state: .init(),
            decodeTimeline: DecodeSessionLogTimelineUseCase(
                rawLogRepository: connectionSessionRepository,
                definitionRepository: MacOSApplicationComposition.makeOBDPIDDefinitionRepository()
            ),
            prepareRawLog: PrepareConnectionSessionRawLogUseCase(
                sessionRepository: connectionSessionRepository,
                rawLogRepository: connectionSessionRepository,
                transferRepository: CloudKitConnectionSessionTransferRepository()
            )
        )
        let connectionSessionLifecycleModel = ConnectionSessionLifecycleModel(
            repository: connectionSessionRepository,
            rawLogRepository: connectionSessionRepository,
            acquisitionDevice: MacOSApplicationComposition.makeConnectionSessionAcquisitionDevice(),
            historyDidChange: { connectionHistoryModel.send(.localDataChanged) },
            endedSessionUploadRequested: { session in
                connectionHistoryModel.send(.sessionUploadRequested(session.id))
            }
        )
        let liveTelemetryModel = MacOSApplicationComposition.makeLiveTelemetryModel(
            sessionDidEnd: { connectionSessionLifecycleModel.send(.endRequested($0)) },
            distanceDidChange: { connectionSessionLifecycleModel.send(.distanceObserved($0)) },
            rawResponseDidReceive: { observation in
                try await MainActor.run {
                    try connectionSessionLifecycleModel.recordRawResponse(observation)
                }
            }
        )
        let vehicleManagementModel = MacOSApplicationComposition.makeVehicleManagementModel(
            connectionSessionRepository: connectionSessionRepository,
            vehicleSessionsDidDelete: { connectionHistoryModel.send(.refreshRequested) }
        ) { vehicle, endpoint, identification in
            connectionSessionLifecycleModel.send(.startRequested)
            connectionSessionLifecycleModel.send(.vehicleResolved(vehicle))
            let mode: LiveTelemetryAcquisitionMode = ZD8VehicleModelPolicy().matches(identification.vin)
                || ZD8VehicleModelPolicy().matches(identification.obdIdentifier)
                ? .brzBetaPeriodic
                : .standardPolling
            liveTelemetryModel.send(.startRequested(endpoint, vehicle.id, mode))
        }
        _authenticationModel = State(
            initialValue: MacOSApplicationComposition.makeAuthenticationSessionModel(
                connectionSessionStorage: connectionSessionRepository
            )
        )
        _accountSettingsModel = State(
            initialValue: MacOSApplicationComposition.makeAccountSettingsModel()
        )
        _macOSSettingsModel = State(
            initialValue: MacOSApplicationComposition.makeSettingsPresentationModel()
        )
        _vehicleManagementModel = State(
            initialValue: vehicleManagementModel
        )
        _liveTelemetryModel = State(
            initialValue: liveTelemetryModel
        )
        _connectionSessionLifecycleModel = State(initialValue: connectionSessionLifecycleModel)
        _connectionHistoryModel = State(initialValue: connectionHistoryModel)
        _sessionLogAnalysisModel = State(initialValue: sessionLogAnalysisModel)
        startVehicleConnection = StartVehicleConnectionUseCase(
            identifyVehicle: { vehicleManagementModel.send(.identifyRequested($0)) }
        )
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
        }
    }

    /// アプリが操作可能へ戻ったとき認証済みセッション概要を再同期します。
    ///
    /// 責務: 1件のScene段階変更を認証済み接続履歴の更新要求へ変換します。
    /// - Parameter phase: 現在のScene段階。
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active, authenticationModel.state.phase == .signedIn else { return }
        connectionHistoryModel.send(.refreshRequested)
    }

    /// 認証済みAppleユーザーをConnection以外の設定保存スコープへ反映します。
    ///
    /// 責務: 現在の認証セッション識別子をSettings機能へ1回通知します。
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
        connectionSessionLifecycleModel.send(
            .accountIdentifierChanged(authenticationModel.state.session?.userIdentifier)
        )
        connectionHistoryModel.send(
            .accountIdentifierChanged(authenticationModel.state.session?.userIdentifier)
        )
        connectionHistoryModel.send(
            .automaticUploadChanged(accountSettingsModel.settings.automaticSessionUploadEnabled)
        )
    }

    /// ログアウト状態へ変わったときに設定スコープと端末内表示状態を初期化します。
    ///
    /// 責務: 認証段階の変化をアカウント設定監視解除とプラットフォーム設定状態の再生成へ反映します。
    /// - Parameter phase: Authenticationが確定した新しい認証段階。
    private func handleAuthenticationPhaseChange(_ phase: AuthenticationPhase) {
        guard phase == .signedOut else { return }
        liveTelemetryModel.send(.stopRequested)
        connectionSessionLifecycleModel.send(.accountIdentifierChanged(nil))
        connectionHistoryModel.send(.accountIdentifierChanged(nil))
        accountSettingsModel.send(.accountIdentifierChanged(nil))
        vehicleManagementModel.send(.accountIdentifierChanged(nil))
        #if os(iOS)
        iOSSettingsModel = IOSApplicationComposition.makeSettingsPresentationModel()
        #elseif os(macOS)
        macOSSettingsModel = MacOSApplicationComposition.makeSettingsPresentationModel()
        #endif
    }
}
