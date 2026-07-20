import SwiftUI

/// ProjectZD8のプロセスエントリーポイントとプラットフォーム別ルート画面を構築します。
@main
struct ProjectZD8App: App {
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
        let connectionHistoryModel = ConnectionHistoryModel(
            repository: connectionSessionRepository,
            synchronizeSessions: IOSApplicationComposition.makeConnectionSessionSynchronization(
                storage: connectionSessionRepository
            ),
            removeIPhoneRawLog: RemoveIPhoneSessionRawLogUseCase(
                repository: connectionSessionRepository
            )
        )
        let connectionSessionLifecycleModel = ConnectionSessionLifecycleModel(
            repository: connectionSessionRepository,
            rawLogRepository: connectionSessionRepository,
            historyDidChange: { connectionHistoryModel.send(.refreshRequested) }
        )
        let liveTelemetryModel = IOSApplicationComposition.makeLiveTelemetryModel(
            sessionDidEnd: { connectionSessionLifecycleModel.send(.endRequested($0)) },
            odometerDidChange: { connectionSessionLifecycleModel.send(.odometerObserved(kilometers: $0)) },
            rawResponseDidReceive: { observation in
                try await MainActor.run {
                    try connectionSessionLifecycleModel.recordRawResponse(observation)
                }
            }
        )
        let vehicleManagementModel = IOSApplicationComposition.makeVehicleManagementModel { vehicle, endpoint, identification in
            connectionSessionLifecycleModel.send(.startRequested)
            connectionSessionLifecycleModel.send(.vehicleResolved(vehicle))
            let mode: LiveTelemetryAcquisitionMode = CurrentGenerationBRZVINPolicy().matches(identification.vin)
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
        startVehicleConnection = StartVehicleConnectionUseCase(
            identifyVehicle: { vehicleManagementModel.send(.identifyRequested($0)) }
        )
        #endif

        #if os(macOS)
        let connectionSessionRepository = MacOSApplicationComposition.makeConnectionSessionRepository()
        let connectionHistoryModel = ConnectionHistoryModel(
            repository: connectionSessionRepository,
            synchronizeSessions: MacOSApplicationComposition.makeConnectionSessionSynchronization(
                storage: connectionSessionRepository
            ),
            deleteSessionEverywhere: DeleteConnectionSessionEverywhereUseCase(
                localRepository: connectionSessionRepository,
                transferRepository: CloudKitConnectionSessionTransferRepository()
            )
        )
        let connectionSessionLifecycleModel = ConnectionSessionLifecycleModel(
            repository: connectionSessionRepository,
            rawLogRepository: connectionSessionRepository,
            historyDidChange: { connectionHistoryModel.send(.refreshRequested) }
        )
        let liveTelemetryModel = MacOSApplicationComposition.makeLiveTelemetryModel(
            sessionDidEnd: { connectionSessionLifecycleModel.send(.endRequested($0)) },
            odometerDidChange: { connectionSessionLifecycleModel.send(.odometerObserved(kilometers: $0)) },
            rawResponseDidReceive: { observation in
                try await MainActor.run {
                    try connectionSessionLifecycleModel.recordRawResponse(observation)
                }
            }
        )
        let vehicleManagementModel = MacOSApplicationComposition.makeVehicleManagementModel { vehicle, endpoint, identification in
            connectionSessionLifecycleModel.send(.startRequested)
            connectionSessionLifecycleModel.send(.vehicleResolved(vehicle))
            let mode: LiveTelemetryAcquisitionMode = CurrentGenerationBRZVINPolicy().matches(identification.vin)
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
        }
    }

    /// 認証済みAppleユーザーをConnection以外の設定保存スコープへ反映します。
    ///
    /// 責務: 現在の認証セッション識別子をSettings機能へ1回通知します。
    private func activateAuthenticatedSettingsScope() {
        accountSettingsModel.send(
            .accountIdentifierChanged(authenticationModel.state.session?.userIdentifier)
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
