#if os(macOS)
import Foundation

/// macOSアプリのルート画面が使うモデル一式です。
///
/// `ProjectZD8App` の生成時に1回だけ組み立てます。組み立ての順序・渡す値は `ProjectZD8App.init` にあった時と同じです。
@MainActor
struct MacOSApplicationRoot {
    /// ルート画面の表示可否を決定する認証セッションモデルです。
    let authenticationModel: AuthenticationSessionModel
    /// Connectionを除く設定をアカウント単位で保持するモデルです。
    let accountSettingsModel: AccountSettingsModel
    /// macOS設定画面へ注入するプレゼンテーションモデルです。
    let settingsModel: MacOSSettingsPresentationModel
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

    /// 接続履歴の保存先と、それを共有するモデル群です。
    private struct SessionModels {
        /// 取得区間の匿名計測境界です。
        let performanceEvents: any AcquisitionPerformanceEventPort
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
    }

    /// macOSのルートモデル一式を組み立てます。
    ///
    /// 責務: 保存先と各Featureのモデルを、従来と同じ順序・同じ値で生成して結び付けます。
    /// - Returns: macOSのルートモデル一式。
    static func make() -> MacOSApplicationRoot {
        let sessions = makeSessionModels()
        let lifecycle = sessions.lifecycle
        let liveTelemetryModel = MacOSApplicationComposition.makeLiveTelemetryModel(
            database: sessions.database,
            acquisitionStorage: sessions.storage.acquisition,
            activeSessionID: { await lifecycle.activeSession?.id },
            performanceEvents: sessions.performanceEvents,
            sessionDidEnd: { lifecycle.send(.endRequested($0)) },
            distanceDidChange: { lifecycle.send(.distanceObserved($0)) }
        )
        let vehicleManagementModel = makeVehicleManagementModel(sessions: sessions, liveTelemetryModel: liveTelemetryModel)
        let maintenanceModel = MacOSApplicationComposition.makeMaintenanceModel(database: sessions.database)
        return MacOSApplicationRoot(
            authenticationModel: MacOSApplicationComposition.makeAuthenticationSessionModel(
                database: sessions.database,
                connectionSessionStorage: sessions.storage.sessions
            ),
            accountSettingsModel: MacOSApplicationComposition.makeAccountSettingsModel(),
            settingsModel: MacOSApplicationComposition.makeSettingsPresentationModel(),
            vehicleManagementModel: vehicleManagementModel,
            maintenanceModel: maintenanceModel,
            liveTelemetryModel: liveTelemetryModel,
            connectionSessionLifecycleModel: lifecycle,
            connectionHistoryModel: sessions.history,
            sessionLogAnalysisModel: sessions.analysis,
            startVehicleConnection: StartVehicleConnectionUseCase(
                identifyVehicle: { vehicleManagementModel.send(.identifyRequested($0)) }
            )
        )
    }

    /// 接続履歴の保存先と、それを共有する履歴・解析・接続セッションのモデルを生成します。
    ///
    /// 責務: 共有DB接続から接続履歴の保存先を作り、履歴・解析・接続セッションのモデルへ結び付けます。
    /// - Returns: 計測境界・DB接続・保存先と3つのモデル。
    private static func makeSessionModels() -> SessionModels {
        let performanceEvents = MacOSApplicationComposition.makeAcquisitionPerformanceEventPort()
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
                definitionRepository: MacOSApplicationComposition.makeOBDPIDDefinitionRepository(database: database)
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
            acquisitionDevice: MacOSApplicationComposition.makeConnectionSessionAcquisitionDevice(),
            historyDidChange: { history.send(.localDataChanged) },
            endedSessionUploadRequested: { session in
                history.send(.sessionUploadRequested(session.id))
            }
        )
        return SessionModels(
            performanceEvents: performanceEvents,
            database: database,
            storage: storage,
            history: history,
            analysis: analysis,
            lifecycle: lifecycle
        )
    }

    /// 接続履歴の同期・削除・Raw管理を注入した履歴モデルを生成します。
    ///
    /// 責務: macOSの接続履歴保存先をCloudKit同期と履歴操作のユースケースへ結び付けます。
    /// - Parameter repository: 接続履歴とRawログの共通保存先。
    /// - Returns: アカウント未確定の履歴モデル。
    private static func makeConnectionHistoryModel(
        repository: ConnectionSessionStorageDependencies.SessionStorage
    ) -> ConnectionHistoryModel {
        ConnectionHistoryModel(
            repository: repository,
            synchronizeSessions: MacOSApplicationComposition.makeConnectionSessionSynchronization(storage: repository),
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

    /// 手動接続で確定した車両から記録を始める車両管理モデルを生成します。
    ///
    /// 責務: 車両確定時に接続セッションの開始・車両確定とテレメトリの開始を従来の順序で送ります。
    /// - Parameters:
    ///   - sessions: 接続履歴の保存先とモデル。
    ///   - liveTelemetryModel: テレメトリの取得を保持するモデル。
    /// - Returns: 車両管理モデル。
    private static func makeVehicleManagementModel(
        sessions: SessionModels,
        liveTelemetryModel: LiveTelemetryModel
    ) -> VehicleManagementModel {
        let lifecycle = sessions.lifecycle
        let history = sessions.history
        return MacOSApplicationComposition.makeVehicleManagementModel(
            database: sessions.database,
            connectionSessionRepository: sessions.storage.sessions,
            vehicleSessionsDidDelete: { history.send(.refreshRequested) }
        ) { vehicle, endpoint, identification in
            lifecycle.send(.startRequested)
            lifecycle.send(.vehicleResolved(vehicle))
            let vehicleModelCode = ZD8VehicleModelPolicy().matches(identification.vin)
                || ZD8VehicleModelPolicy().matches(identification.obdIdentifier)
                ? ZD8VehicleModelPolicy.modelCode
                : nil
            liveTelemetryModel.send(
                .startRequested(
                    LiveTelemetryStartRequest(endpoint: endpoint, vehicleID: vehicle.id, vehicleModelCode: vehicleModelCode)
                )
            )
        }
    }
}
#endif
