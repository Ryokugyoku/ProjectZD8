#if os(iOS)
import Foundation

/// iOSアプリのルート画面と常駐リンク監視が使うモデル一式です。
///
/// `ProjectZD8App` の生成時に1回だけ組み立てます。組み立ては段階ごとの関数に分け、各モデル間の連携はクロージャで結び付けます。
@MainActor
struct IOSApplicationRoot {
    /// ルート画面の表示可否を決定する認証セッションモデルです。
    let authenticationModel: AuthenticationSessionModel
    /// Connectionを除く設定をアカウント単位で保持するモデルです。
    let accountSettingsModel: AccountSettingsModel
    /// iOS設定画面へ注入するプレゼンテーションモデルです。
    let settingsModel: IOSSettingsPresentationModel
    /// 自動記録設定と記録開始方法の選択画面の状態を保持するモデルです。
    let automaticRecordingModel: AutomaticRecordingPreferenceModel
    /// 未登録車両の警告を保持するモデルです。
    let unassignedVINWarningModel: UnassignedObservedVINWarningModel
    /// 登録車両、VIN確認、CloudKit同期を保持するモデルです。
    let vehicleManagementModel: VehicleManagementModel
    /// 車両別の軽整備・重整備とCloudKit同期を保持するモデルです。
    let maintenanceModel: MaintenanceModel
    /// 主要PIDの継続取得状態を保持するモデルです。
    let liveTelemetryModel: LiveTelemetryModel
    /// 接続セッションの開始、車両関連付け、終了を保持するモデルです。
    let connectionSessionLifecycleModel: ConnectionSessionLifecycleModel
    /// アカウント単位の接続履歴を保持するモデルです。
    let connectionHistoryModel: ConnectionHistoryModel
    /// 保存済みPIDログの読取専用解析状態を保持するモデルです。
    let sessionLogAnalysisModel: SessionLogAnalysisModel
    /// HOME接続要求を車両識別とPID継続取得へ展開するユースケースです。
    let startVehicleConnection: StartVehicleConnectionUseCase
    /// アプリ側の事実を常駐リンク監視へ伝える型です。
    let adapterLinkSupervision: IOSAdapterLinkSupervisionDriver

    /// 接続履歴の保存先と、それを共有するモデル群です。
    private struct SessionModels {
        /// 共有製品DB接続です。
        let database: ApplicationDatabaseConnection
        /// 接続履歴・Raw・取得証跡の保存先です。
        let storage: ConnectionSessionStorageDependencies
        /// アカウント単位の接続履歴を保持するモデルです。
        let history: ConnectionHistoryModel
        /// 保存済みPIDログの解析状態を保持するモデルです。
        let analysis: SessionLogAnalysisModel
        /// 接続セッションの開始・終了を保持するモデルです。
        let lifecycle: ConnectionSessionLifecycleModel
        /// 取得区間の匿名計測境界です。
        let performanceEvents: any AcquisitionPerformanceEventPort
    }

    /// iOSのルートモデル一式を組み立てます。
    ///
    /// 責務: 保存先・常駐リンク・記録の調停役・各Featureのモデルを生成し、通知応答の受け口を有効にします。
    /// - Returns: 常駐リンク監視が未開始のルートモデル一式。`adapterLinkSupervision.launch()` で開始します。
    /// - Side Effects: 通知センターの delegate を車両検知通知へ置き換えます(起動完了前に呼ぶこと)。
    static func make() -> IOSApplicationRoot {
        let sessions = makeSessionModels()
        let authenticationModel = IOSApplicationComposition.makeAuthenticationSessionModel(
            database: sessions.database,
            connectionSessionStorage: sessions.storage.sessions
        )
        let residentLink = IOSResidentAdapterLink.make()
        let coordinator = IOSAdapterLinkComposition.makeRecordingCoordinator(
            lifecycle: sessions.lifecycle,
            authentication: authenticationModel
        )
        let liveTelemetryModel = makeLiveTelemetryModel(sessions: sessions, residentLink: residentLink, coordinator: coordinator)
        let vehicleManagementModel = makeVehicleManagementModel(
            sessions: sessions,
            residentLink: residentLink,
            coordinator: coordinator
        )
        let notifier = IOSVehicleDetectionNotifier()
        notifier.activateResponseHandling()
        let supervision = IOSAdapterLinkComposition.makeSupervision(
            residentLink: residentLink,
            notifier: notifier,
            recordingControl: coordinator
        )
        return IOSApplicationRoot(
            authenticationModel: authenticationModel,
            accountSettingsModel: IOSApplicationComposition.makeAccountSettingsModel(),
            settingsModel: IOSApplicationComposition.makeSettingsPresentationModel(),
            automaticRecordingModel: IOSApplicationComposition.makeAutomaticRecordingPreferenceModel(),
            unassignedVINWarningModel: IOSApplicationComposition.makeUnassignedObservedVINWarningModel(
                repository: sessions.storage.sessions
            ),
            vehicleManagementModel: vehicleManagementModel,
            maintenanceModel: IOSApplicationComposition.makeMaintenanceModel(database: sessions.database),
            liveTelemetryModel: liveTelemetryModel,
            connectionSessionLifecycleModel: sessions.lifecycle,
            connectionHistoryModel: sessions.history,
            sessionLogAnalysisModel: sessions.analysis,
            startVehicleConnection: StartVehicleConnectionUseCase(
                identifyVehicle: { vehicleManagementModel.send(.identifyRequested($0)) }
            ),
            adapterLinkSupervision: IOSAdapterLinkSupervisionDriver(
                supervision: supervision,
                authentication: authenticationModel,
                accountIdentifierDidChange: { sessions.lifecycle.send(.accountIdentifierChanged($0)) }
            )
        )
    }

    /// 接続履歴の保存先と、それを共有する履歴・解析・接続セッションのモデルを生成します。
    ///
    /// 責務: 共有DB接続から接続履歴の保存先を作り、履歴・解析・接続セッションのモデルへ結び付けます。
    /// - Returns: 保存先と3つのモデル。
    private static func makeSessionModels() -> SessionModels {
        let performanceEvents = IOSApplicationComposition.makeAcquisitionPerformanceEventPort()
        let database = ApplicationDatabaseConnection()
        let storage = ConnectionSessionStorageDependencies.makeProduction(
            openDatabaseQueue: database.databaseQueue,
            performanceEvents: performanceEvents
        )
        let history = makeConnectionHistoryModel(repository: storage.sessions)
        let analysis = SessionLogAnalysisModel(
            state: .init(),
            decodeTimeline: DecodeSessionLogTimelineUseCase(
                rawLogRepository: storage.sessions,
                definitionRepository: IOSApplicationComposition.makeOBDPIDDefinitionRepository(database: database)
            ),
            prepareRawLog: PrepareConnectionSessionRawLogUseCase(
                sessionRepository: storage.sessions,
                rawLogRepository: storage.sessions,
                transferRepository: CloudKitConnectionSessionTransferRepository()
            )
        )
        let lifecycle = ConnectionSessionLifecycleModel(
            repository: storage.sessions,
            rawLogRepository: storage.sessions,
            acquisitionTerminationRepository: storage.acquisition,
            acquisitionDevice: IOSApplicationComposition.makeConnectionSessionAcquisitionDevice(),
            historyDidChange: { history.send(.localDataChanged) },
            endedSessionUploadRequested: { session in
                history.send(.sessionUploadRequested(session.id))
            }
        )
        return SessionModels(
            database: database,
            storage: storage,
            history: history,
            analysis: analysis,
            lifecycle: lifecycle,
            performanceEvents: performanceEvents
        )
    }

    /// 接続履歴の同期・削除・Raw管理を注入した履歴モデルを生成します。
    ///
    /// 責務: iPhoneの接続履歴保存先をCloudKit同期と履歴操作のユースケースへ結び付けます。
    /// - Parameter repository: 接続履歴とRawログの共通保存先。
    /// - Returns: アカウント未確定の履歴モデル。
    private static func makeConnectionHistoryModel(
        repository: ConnectionSessionStorageDependencies.SessionStorage
    ) -> ConnectionHistoryModel {
        ConnectionHistoryModel(
            repository: repository,
            synchronizeSessions: IOSApplicationComposition.makeConnectionSessionSynchronization(storage: repository),
            releaseRawCache: ReleaseConnectionSessionRawCacheUseCase(repository: repository),
            deleteSessionEverywhere: DeleteConnectionSessionEverywhereUseCase(
                localRepository: repository,
                transferRepository: CloudKitConnectionSessionTransferRepository()
            ),
            reviewInterruptedSession: ReviewInterruptedConnectionSessionUseCase(repository: repository),
            evictStaleRawLogs: EvictStaleConnectionSessionRawLogsUseCase(
                sessionRepository: repository,
                rawLogRepository: repository
            )
        )
    }

    /// 常駐リンクと記録の調停役へ結び付けたテレメトリモデルを生成します。
    ///
    /// 責務: テレメトリの終了を接続セッションの終了と調停役へ伝え、調停役のテレメトリ開始・停止をこのモデルへ結び付けます。
    /// - Parameters:
    ///   - sessions: 接続履歴の保存先とモデル。
    ///   - residentLink: 常駐リンク一式。
    ///   - coordinator: 記録の調停役。
    /// - Returns: 車両なしの記録開始にも対応するテレメトリモデル。
    private static func makeLiveTelemetryModel(
        sessions: SessionModels,
        residentLink: IOSResidentAdapterLink,
        coordinator: VehicleRecordingCoordinator
    ) -> LiveTelemetryModel {
        let lifecycle = sessions.lifecycle
        let model = IOSApplicationComposition.makeLiveTelemetryModel(
            database: sessions.database,
            residentLink: residentLink,
            acquisitionStorage: sessions.storage.acquisition,
            activeSessionID: { await lifecycle.activeSession?.id },
            performanceEvents: sessions.performanceEvents,
            sessionDidEnd: { reason in
                lifecycle.send(.endRequested(reason))
                coordinator.telemetryDidEnd()
            },
            distanceDidChange: { lifecycle.send(.distanceObserved($0)) }
        )
        IOSAdapterLinkComposition.connectTelemetry(of: coordinator, to: model)
        return model
    }

    /// 手動接続の記録開始と登録後の紐付けを結び付けた車両管理モデルを生成します。
    ///
    /// 責務: 手動接続の車両識別の開始・終了と確定した車両を調停役へ、新規登録を観測VINセッションの紐付けへ結び付けます。
    /// - Parameters:
    ///   - sessions: 接続履歴の保存先とモデル。
    ///   - residentLink: 常駐リンク一式。
    ///   - coordinator: 記録の調停役。
    /// - Returns: 車両管理モデル。
    private static func makeVehicleManagementModel(
        sessions: SessionModels,
        residentLink: IOSResidentAdapterLink,
        coordinator: VehicleRecordingCoordinator
    ) -> VehicleManagementModel {
        let history = sessions.history
        let assignSessions = AssignVehicleToObservedVINConnectionSessionsUseCase(
            repository: sessions.storage.sessions,
            historyDidChange: { history.send(.localDataChanged) }
        )
        return IOSApplicationComposition.makeVehicleManagementModel(
            database: sessions.database,
            residentLink: residentLink,
            connectionSessionRepository: sessions.storage.sessions,
            vehicleSessionsDidDelete: { history.send(.refreshRequested) },
            connectionVehicleDidResolve: { vehicle, endpoint, identification in
                coordinator.startManualRecording(
                    .manualConnection(vehicle: vehicle, endpoint: endpoint, identification: identification)
                )
            },
            vehicleDidRegister: { vehicle, accountIdentifier in
                _ = try assignSessions.execute(vehicle: vehicle, accountIdentifier: accountIdentifier)
            },
            connectionIdentificationWillBegin: { coordinator.manualConnectionIdentificationWillBegin() },
            connectionIdentificationDidEnd: { coordinator.manualConnectionIdentificationDidEnd() }
        )
    }
}
#endif
