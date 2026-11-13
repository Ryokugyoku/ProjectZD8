import Foundation
import OSLog

/// アプリ全体の依存を1か所で組み立て、各画面のモデルを保持します。
@MainActor
final class AppComposition {
    let deviceConnection: DeviceConnectionModel
    let driveSession: DriveSessionModel
    let liveTelemetry: LiveTelemetryModel
    let vehicles: VehicleManagementModel
    let maintenance: MaintenanceModel
    let logHistory: LogHistoryModel
    let settings: SettingsModel
    let sync: SyncModel
    let analysis: AnalysisModel
    /// 分析ワークベンチの同梱ファイルとデータセットを解決します。
    let analysisContent: ResolveAnalysisWebContentUseCase

    private let cloudSync: any CloudSyncPort
    private let evictExpiredSamples: EvictExpiredSamplesUseCase
    private var hasLaunched = false
    private let logger = Logger(subsystem: "Ryokugyoku.ProjectZD8", category: "launch")

    /// 本番の依存を組み立てます。
    ///
    /// 責務: データベースを開き、全リポジトリ・ポート実装・モデルを生成して接続します。
    /// - Parameters:
    ///   - discovery: この端末のアダプター探索。
    ///   - sleepInhibitor: この端末のスリープ抑止。
    ///   - defaultLocalRawRetention: この端末種別でのRaw保持期間の既定値。
    /// - Throws: データベースまたは写真の保存先を準備できない場合のエラー。
    init(
        discovery: any AdapterDiscoveryPort,
        sleepInhibitor: any SleepInhibitingPort,
        defaultLocalRawRetention: LocalRawRetention
    ) throws {
        let database = try AppDatabase.openApplicationDatabase()
        let photoFiles = try PhotoFileStore.application()
        let defaults = UserDefaults.standard
        let now: @Sendable () -> Date = { Date() }

        let vehicleRepository = GRDBVehicleRepository(database: database, photoFiles: photoFiles, now: now)
        let pidSettingRepository = GRDBVehiclePIDSettingRepository(database: database)
        let maintenanceRepository = GRDBMaintenanceRepository(database: database, photoFiles: photoFiles, now: now)
        let photoRepository = GRDBPhotoRepository(database: database, files: photoFiles, now: now)
        let sessionRepository = GRDBSessionRepository(database: database, now: now)
        let changes = GRDBStoreChangeObserver(database: database)

        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults, defaultLocalRawRetention: defaultLocalRawRetention)
        let environment = BundleAcquisitionEnvironment()
        let runtime = environment.environment()
        let settings = SettingsModel(store: settingsStore, appVersion: runtime.appVersion, appBuild: runtime.appBuild)
        self.settings = settings

        let cloudSync: any CloudSyncPort = CloudKitAvailability.isCloudKitUsable()
            ? CloudKitSyncEngine(database: database, photoFiles: photoFiles)
            : LocalOnlyCloudSync(database: database, photoFiles: photoFiles)
        self.cloudSync = cloudSync
        sync = SyncModel(sync: cloudSync)

        let broadcaster = LiveTelemetryFeedBroadcaster()
        liveTelemetry = LiveTelemetryModel(feed: broadcaster)
        let driveSession = DriveSessionModel(
            linkPort: SystemOBDLinkPort(),
            vehicles: vehicleRepository,
            sessions: sessionRepository,
            preparePIDs: PrepareSessionPIDsUseCase(settings: pidSettingRepository, now: now),
            environment: environment,
            sleepInhibitor: sleepInhibitor,
            events: broadcaster,
            clock: SystemAcquisitionClock(),
            now: now,
            onSessionEnded: { _ in }
        )
        self.driveSession = driveSession
        deviceConnection = DeviceConnectionModel(
            discovery: discovery,
            defaultStore: UserDefaultsDefaultAdapterStore(defaults: defaults),
            isDemoModeEnabled: { settings.settings.isDemoModeEnabled },
            demoAdapter: DemoOBDLink.adapter,
            connectRequested: { driveSession.send(.connectRequested($0)) }
        )

        vehicles = VehicleManagementModel(
            vehicles: vehicleRepository,
            sessions: sessionRepository,
            pidSettings: pidSettingRepository,
            photos: photoRepository,
            changes: changes
        )
        maintenance = MaintenanceModel(
            vehicles: vehicleRepository,
            maintenance: maintenanceRepository,
            photos: photoRepository,
            changes: changes
        )
        logHistory = LogHistoryModel(sessions: sessionRepository, vehicles: vehicleRepository, changes: changes)
        evictExpiredSamples = EvictExpiredSamplesUseCase(sessions: sessionRepository, settings: settingsStore, now: now)

        let datasetStore = AnalysisDatasetStore()
        let decoder = AnalysisSessionDecoder(sessions: sessionRepository)
        let names = BundleAnalysisPIDNameResolver()
        analysis = AnalysisModel(
            languageCode: Bundle.main.preferredLocalizations.first ?? "ja",
            sessions: sessionRepository,
            vehicles: vehicleRepository,
            cloudSync: cloudSync,
            buildDataset: BuildAnalysisDatasetUseCase(decoder: decoder, vehicles: vehicleRepository, maintenance: maintenanceRepository, names: names),
            buildTrend: BuildVehicleTrendDatasetUseCase(sessions: sessionRepository, decoder: decoder, vehicles: vehicleRepository, maintenance: maintenanceRepository, names: names),
            store: datasetStore
        )
        analysisContent = ResolveAnalysisWebContentUseCase(
            resourceDirectory: Bundle.main.resourceURL ?? Bundle.main.bundleURL,
            store: datasetStore
        )
    }

    /// 起動時に1回だけ行う処理を実行します。
    ///
    /// 責務: 前回閉じられなかったセッションの終了、同期の開始、保持期間を過ぎたRawの解放を1回だけ行います。
    func launch() {
        guard !hasLaunched else { return }
        hasLaunched = true
        driveSession.send(.appLaunched)
        Task { [cloudSync] in await cloudSync.start() }
        Task { [evictExpiredSamples, logger] in
            do {
                let result = try await evictExpiredSamples.execute()
                if !result.failed.isEmpty {
                    logger.error("Raw eviction failed for \(result.failed.count) session(s)")
                }
            } catch {
                logger.error("Raw eviction could not run: \(String(describing: error))")
            }
        }
    }
}
