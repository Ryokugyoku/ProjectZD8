/// iOSとmacOSで共通の、ルートのモデル一式とモデル間の配線を組み立てる手順です。
///
/// OS固有の生成は `ApplicationPlatformComposing` に任せ、生成順序・共有インスタンス・通知クロージャの捕捉先を
/// この1か所で決めます。各モデルと保存先は1回だけ生成し、同じインスタンスを必要な相手へ渡します。
@MainActor
enum ApplicationRootAssembly {
    /// ルートのモデル一式を組み立てます。
    ///
    /// 責務: 計測境界・DB接続・接続セッション保存先を1回ずつ生成し、それらを共有する各モデルを決まった順序で生成します。
    /// - Parameter platform: OS固有の生成手順。
    /// - Returns: ルートが保持するモデル一式。
    static func makeModels<Platform: ApplicationPlatformComposing>(_ platform: Platform.Type) -> ApplicationRootModels {
        let performanceEvents = Platform.makeAcquisitionPerformanceEventPort()
        let database = ApplicationDatabaseConnection()
        let storage = ConnectionSessionStorageDependencies.makeProduction(
            openDatabaseQueue: database.databaseQueue,
            performanceEvents: performanceEvents
        )
        let repository = storage.sessions
        let history = makeConnectionHistoryModel(platform, repository: repository)
        let analysis = makeSessionLogAnalysisModel(platform, database: database, repository: repository)
        let lifecycle = makeLifecycleModel(platform, storage: storage, history: history)
        let liveTelemetry = makeLiveTelemetryModel(
            platform,
            database: database,
            storage: storage,
            performanceEvents: performanceEvents,
            lifecycle: lifecycle
        )
        let vehicleManagement = makeVehicleManagementModel(
            platform,
            database: database,
            repository: repository,
            history: history,
            lifecycle: lifecycle,
            liveTelemetry: liveTelemetry
        )
        let maintenance = Platform.makeMaintenanceModel(database: database)
        let authentication = Platform.makeAuthenticationSessionModel(database: database, connectionSessionStorage: repository)
        return ApplicationRootModels(
            authentication: authentication,
            accountSettings: Platform.makeAccountSettingsModel(),
            vehicleManagement: vehicleManagement,
            maintenance: maintenance,
            liveTelemetry: liveTelemetry,
            connectionSessionLifecycle: lifecycle,
            connectionHistory: history,
            sessionLogAnalysis: analysis
        )
    }

    /// HOME接続要求を車両識別へ展開するユースケースを組み立てます。
    ///
    /// 責務: 接続要求を指定の車両管理モデルの識別要求へ結び付けます。
    /// - Parameter vehicleManagement: 識別要求を受ける車両管理モデル。
    /// - Returns: HOME接続要求のユースケース。
    static func makeStartVehicleConnection(vehicleManagement: VehicleManagementModel) -> StartVehicleConnectionUseCase {
        StartVehicleConnectionUseCase(identifyVehicle: { vehicleManagement.send(.identifyRequested($0)) })
    }

    /// 接続履歴のモデルを組み立てます。
    ///
    /// 責務: OSの同期と、同じ接続セッション保存先を使う履歴操作のユースケースを履歴モデルへ注入します。
    /// - Parameters:
    ///   - platform: OS固有の生成手順。
    ///   - repository: 接続セッションの保存先。
    /// - Returns: 接続履歴のモデル。
    private static func makeConnectionHistoryModel<Platform: ApplicationPlatformComposing>(
        _ platform: Platform.Type,
        repository: ConnectionSessionStorageDependencies.SessionStorage
    ) -> ConnectionHistoryModel {
        let synchronization = Platform.makeConnectionSessionSynchronization(storage: repository)
        return ConnectionHistoryModel(
            repository: repository,
            synchronizeSessions: synchronization,
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

    /// 保存済みPIDログ解析のモデルを組み立てます。
    ///
    /// 責務: 接続セッションのRawログとPID定義を解析モデルへ注入します。
    /// - Parameters:
    ///   - platform: OS固有の生成手順。
    ///   - database: 製品DB接続。
    ///   - repository: 接続セッションの保存先。
    /// - Returns: 保存済みPIDログ解析のモデル。
    private static func makeSessionLogAnalysisModel<Platform: ApplicationPlatformComposing>(
        _ platform: Platform.Type,
        database: ApplicationDatabaseConnection,
        repository: ConnectionSessionStorageDependencies.SessionStorage
    ) -> SessionLogAnalysisModel {
        SessionLogAnalysisModel(
            state: .init(),
            decodeTimeline: DecodeSessionLogTimelineUseCase(
                rawLogRepository: repository,
                definitionRepository: Platform.makeOBDPIDDefinitionRepository(database: database)
            ),
            prepareRawLog: PrepareConnectionSessionRawLogUseCase(
                sessionRepository: repository,
                rawLogRepository: repository,
                transferRepository: CloudKitConnectionSessionTransferRepository()
            )
        )
    }

    /// 接続セッションのライフサイクルのモデルを組み立てます。
    ///
    /// 責務: 接続セッション保存先・取得終了・プロセス復帰の処理と、履歴モデルへの通知を結び付けます。
    /// - Parameters:
    ///   - platform: OS固有の生成手順。
    ///   - storage: 接続セッション保存先一式。
    ///   - history: 保存後の再読込とアップロードを通知する履歴モデル。
    /// - Returns: 接続セッションのライフサイクルのモデル。
    private static func makeLifecycleModel<Platform: ApplicationPlatformComposing>(
        _ platform: Platform.Type,
        storage: ConnectionSessionStorageDependencies,
        history: ConnectionHistoryModel
    ) -> ConnectionSessionLifecycleModel {
        ConnectionSessionLifecycleModel(
            repository: storage.sessions,
            rawLogRepository: storage.sessions,
            acquisitionTerminationRepository: storage.acquisition,
            acquisitionDevice: Platform.makeConnectionSessionAcquisitionDevice(),
            historyDidChange: { history.send(.localDataChanged) },
            endedSessionUploadRequested: { session in
                history.send(.sessionUploadRequested(session.id))
            },
            recoverRelaunchedSession: storage.makeRelaunchRecovery()
        )
    }

    /// PID継続取得のモデルを組み立てます。
    ///
    /// 責務: 現在セッションの識別子・終了・累積距離をライフサイクルのモデルへ結び付けます。
    /// - Parameters:
    ///   - platform: OS固有の生成手順。
    ///   - database: 製品DB接続。
    ///   - storage: 接続セッション保存先一式。
    ///   - performanceEvents: 取得区間を通知する匿名計測境界。
    ///   - lifecycle: 終了と累積距離を受けるライフサイクルのモデル。
    /// - Returns: PID継続取得のモデル。
    private static func makeLiveTelemetryModel<Platform: ApplicationPlatformComposing>(
        _ platform: Platform.Type,
        database: ApplicationDatabaseConnection,
        storage: ConnectionSessionStorageDependencies,
        performanceEvents: any AcquisitionPerformanceEventPort,
        lifecycle: ConnectionSessionLifecycleModel
    ) -> LiveTelemetryModel {
        Platform.makeLiveTelemetryModel(
            database: database,
            connectionSessionStorage: storage,
            activeSessionID: { await lifecycle.activeSession?.id },
            performanceEvents: performanceEvents,
            sessionDidEnd: { reason, endedAt in lifecycle.send(.endRequested(reason, endedAt: endedAt)) },
            distanceDidChange: { lifecycle.send(.distanceObserved($0)) }
        )
    }

    /// 車両管理のモデルを組み立てます。
    ///
    /// 責務: 車両識別の結果を、接続セッションとPID継続取得の開始、途中登録の車両の関連付けへ結び付けます。
    /// - Parameters:
    ///   - platform: OS固有の生成手順。
    ///   - database: 製品DB接続。
    ///   - repository: 接続セッションの保存先。
    ///   - history: 車両関連セッション削除後に再読込する履歴モデル。
    ///   - lifecycle: 接続セッションのライフサイクルのモデル。
    ///   - liveTelemetry: PID継続取得のモデル。
    /// - Returns: 車両管理のモデル。
    private static func makeVehicleManagementModel<Platform: ApplicationPlatformComposing>(
        _ platform: Platform.Type,
        database: ApplicationDatabaseConnection,
        repository: ConnectionSessionStorageDependencies.SessionStorage,
        history: ConnectionHistoryModel,
        lifecycle: ConnectionSessionLifecycleModel,
        liveTelemetry: LiveTelemetryModel
    ) -> VehicleManagementModel {
        Platform.makeVehicleManagementModel(
            database: database,
            connectionSessionRepository: repository,
            vehicleSessionsDidDelete: { history.send(.refreshRequested) },
            connectionVehicleDidResolve: { vehicle, endpoint, identification in
                VehicleConnectionStartWiring.startRegistered(
                    vehicle,
                    endpoint: endpoint,
                    identification: identification,
                    lifecycle: lifecycle,
                    liveTelemetry: liveTelemetry
                )
            },
            unregisteredConnectionDidStart: { endpoint, _ in
                VehicleConnectionStartWiring.startUnregistered(endpoint: endpoint, lifecycle: lifecycle, liveTelemetry: liveTelemetry)
            },
            unregisteredConnectionVehicleDidRegister: { lifecycle.send(.unregisteredVehicleRegistered($0)) }
        )
    }
}
