/// iOSとmacOSで共通の、応答駆動の取得ループと取得記録を組み立てる手順です。
///
/// OS固有の値(PID取得境界、PID定義・対応PIDの保存先、取得platform、スリープ抑止)は各OSのCompositionから受け取ります。
@MainActor
enum LiveTelemetryModelAssembly {
    /// OS固有の境界を受け取り、取得記録付きのLiveTelemetryモデルを組み立てます。
    ///
    /// 責務: 取得ループ、Loggingの取得記録、単調時計、表示モデルを1組の構成へ結び付けます。
    /// - Parameters:
    ///   - telemetry: PID単位のtyped Transport観測を返す取得境界。
    ///   - definitionRepository: PID定義の保存先。
    ///   - capabilityRepository: 車両別対応PIDの保存先。
    ///   - storage: 接続session・取得証拠・チャンク・区間・欠損の保存先。
    ///   - acquisitionPlatform: manifestへ記録する取得platform。
    ///   - activeSessionID: 現在Logging sessionの識別子を返す境界。
    ///   - performanceEvents: 取得区間を通知する匿名計測境界。
    ///   - sessionDidEnd: PID取得終了原因をLoggingへ通知する処理。
    ///   - distanceDidChange: 取得元付き累積距離をLoggingへ通知する処理。
    ///   - systemSleepInhibitor: 車両接続中だけシステムスリープを抑止する境界。
    /// - Returns: 取得記録付きの取得ループを購読するモデル。
    static func makeModel(
        telemetry: any OBDPIDTelemetryPort,
        definitionRepository: any OBDPIDDefinitionRepository,
        capabilityRepository: any VehiclePIDCapabilityRepository,
        storage: ConnectionSessionStorageDependencies,
        acquisitionPlatform: ConnectionSessionAcquisitionPlatform,
        activeSessionID: @escaping @Sendable () async -> ConnectionSessionID?,
        performanceEvents: any AcquisitionPerformanceEventPort,
        sessionDidEnd: @escaping @MainActor (ConnectionSessionEndReason) -> Void,
        distanceDidChange: @escaping @MainActor (ConnectionSessionDistanceObservation) -> Void,
        systemSleepInhibitor: (any VehicleConnectionSystemSleepInhibiting)?
    ) -> LiveTelemetryModel {
        let clock = ContinuousMonotonicClock()
        let recorder = makeRecorder(
            storage: storage,
            acquisitionPlatform: acquisitionPlatform,
            activeSessionID: activeSessionID,
            clock: clock,
            performanceEvents: performanceEvents
        )
        let readMajorPIDs = ReadMajorOBDPIDsUseCase(definitionRepository: definitionRepository, telemetry: telemetry)
        return LiveTelemetryModel(
            state: LiveTelemetryState(),
            prepareAcquisition: PrepareLiveTelemetryAcquisitionUseCase(
                readMajorPIDs: readMajorPIDs,
                loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase(
                    repository: capabilityRepository,
                    telemetry: telemetry,
                    definitionRepository: definitionRepository
                )
            ),
            acquisitionLoop: LiveTelemetryAcquisitionLoop(telemetry: telemetry, recorder: recorder, clock: clock),
            clock: clock,
            sessionDidEnd: sessionDidEnd,
            distanceDidChange: distanceDidChange,
            systemSleepInhibitor: systemSleepInhibitor
        )
    }

    /// 取得チャンクを保存するLoggingの取得記録を組み立てます。
    ///
    /// 責務: manifest作成、チャンク・区間・欠損の保存先、Raw記録順序の続き、clockを取得記録へ注入します。
    /// - Parameters:
    ///   - storage: 接続session・取得証拠・チャンク・区間・欠損の保存先。
    ///   - acquisitionPlatform: manifestへ記録する取得platform。
    ///   - activeSessionID: 現在Logging sessionの識別子を返す境界。
    ///   - clock: Rawの単調時刻とcommit経過を測る単調時計。
    ///   - performanceEvents: 取得区間を通知する匿名計測境界。
    /// - Returns: 取得ループへ渡す取得記録。
    private static func makeRecorder(
        storage: ConnectionSessionStorageDependencies,
        acquisitionPlatform: ConnectionSessionAcquisitionPlatform,
        activeSessionID: @escaping @Sendable () async -> ConnectionSessionID?,
        clock: any MonotonicClockPort,
        performanceEvents: any AcquisitionPerformanceEventPort
    ) -> ConnectionSessionAcquisitionRecorder {
        let configuration = ProductionConnectionSessionAcquisitionConfiguration.phase4G
        let sessions = storage.sessions
        return ConnectionSessionAcquisitionRecorder(
            createManifest: CreateConnectionSessionAcquisitionManifestUseCase(
                acquisitionRepository: storage.acquisition,
                evidencePort: BundleConnectionSessionAcquisitionEvidenceAdapter(
                    schemaContractVersion: configuration.schemaContractVersion,
                    acquisitionPlatform: acquisitionPlatform
                )
            ),
            chunkRepository: storage.chunks,
            segmentRepository: storage.segments,
            gapRepository: storage.gaps,
            nextRawSequence: { sessionID in
                try await MainActor.run { Int64(try sessions.entryCount(for: sessionID)) }
            },
            activeSessionID: activeSessionID,
            versions: AcquisitionManifestVersions(
                manifestVersion: configuration.manifestVersion,
                pollingPolicyVersion: configuration.pollingPolicyVersion,
                modelInputManifestVersion: configuration.modelInputManifestVersion,
                formulaCanonicalizationVersion: configuration.formulaCanonicalizationVersion
            ),
            clock: clock,
            performanceEvents: performanceEvents
        )
    }
}
