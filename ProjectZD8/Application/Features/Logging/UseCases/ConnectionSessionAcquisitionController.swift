import Foundation

/// Production LiveTelemetry loopをmanifestおよび方式B batch保存へ接続します。
actor ConnectionSessionAcquisitionController: LiveTelemetryAcquisitionEvidencePort {
    /// manifestと開始境界を原子的に保存するuse caseです。
    private let createManifest: CreateConnectionSessionAcquisitionManifestUseCase
    /// typed観測を方式B batchとして保存するuse caseです。
    private let persistBatch: PersistAcquisitionBatchUseCase
    /// 現在Logging sessionの識別子を返す境界です。
    private let activeSessionID: @Sendable () async -> ConnectionSessionID?
    /// manifest構造versionです。
    private let manifestVersion: Int
    /// polling policy契約versionです。
    private let pollingPolicyVersion: Int
    /// model入力変換契約versionです。
    private let modelInputManifestVersion: Int
    /// formula canonicalization契約versionです。
    private let formulaCanonicalizationVersion: Int
    /// batch全体の匿名性能event通知先です。
    private let performanceEvents: any AcquisitionPerformanceEventPort
    /// 現在世代へ保存済みのRaw取得許可です。
    private var permission: ConnectionSessionRawAcquisitionPermission?

    /// Production取得証拠のuse case、session境界、version authorityを固定します。
    ///
    /// 責務: LiveTelemetry portを1組のLogging取得証拠use caseへ結び付けます。
    /// - Parameters:
    ///   - createManifest: manifestと開始境界を原子的に保存するuse case。
    ///   - persistBatch: typed観測を方式B batchとして保存するuse case。
    ///   - activeSessionID: 現在Logging sessionの識別子を返す境界。
    ///   - manifestVersion: manifest構造version。
    ///   - pollingPolicyVersion: polling policy契約version。
    ///   - modelInputManifestVersion: model入力変換契約version。
    ///   - formulaCanonicalizationVersion: formula canonicalization契約version。
    ///   - performanceEvents: batch全体の匿名性能event通知先。
    init(
        createManifest: CreateConnectionSessionAcquisitionManifestUseCase,
        persistBatch: PersistAcquisitionBatchUseCase,
        activeSessionID: @escaping @Sendable () async -> ConnectionSessionID?,
        manifestVersion: Int,
        pollingPolicyVersion: Int,
        modelInputManifestVersion: Int,
        formulaCanonicalizationVersion: Int,
        performanceEvents: any AcquisitionPerformanceEventPort = NoOpAcquisitionPerformanceEventPort()
    ) {
        self.createManifest = createManifest
        self.persistBatch = persistBatch
        self.activeSessionID = activeSessionID
        self.manifestVersion = manifestVersion
        self.pollingPolicyVersion = pollingPolicyVersion
        self.modelInputManifestVersion = modelInputManifestVersion
        self.formulaCanonicalizationVersion = formulaCanonicalizationVersion
        self.performanceEvents = performanceEvents
        permission = nil
    }

    /// manifestと開始境界を保存し、成功した世代だけを取得可能にします。
    ///
    /// 責務: 1世代の確定済み取得入力を保存済みRaw取得許可へ変換します。
    /// - Parameter input: 定義、capability、policy順を含む取得開始入力。
    /// - Throws: session不在、入力不正、stale世代、または保存失敗。
    func start(_ input: LiveTelemetryAcquisitionStartInput) async throws {
        let interval = performanceEvents.begin(
            .acquisitionStart,
            context: AcquisitionPerformanceContext(generation: input.generation)
        )
        guard let sessionID = await activeSessionID() else {
            performanceEvents.end(interval, outcome: .failed)
            throw ConnectionSessionRepositoryError.invalidState
        }
        await createManifest.activate(generation: input.generation)
        await persistBatch.activate(generation: input.generation)
        do {
            permission = try await createManifest.execute(
                CreateConnectionSessionAcquisitionManifestInput(
                    sessionID: sessionID,
                    generation: input.generation,
                    manifestVersion: manifestVersion,
                    pollingPolicyVersion: pollingPolicyVersion,
                    modelInputManifestVersion: modelInputManifestVersion,
                    formulaCanonicalizationVersion: formulaCanonicalizationVersion,
                    pidDefinitions: input.definitions,
                    pidCapabilities: input.capabilities,
                    orderedRequestedPIDs: input.orderedRequests
                )
            )
            performanceEvents.end(interval, outcome: .succeeded)
        } catch {
            await persistBatch.cancel(generation: input.generation)
            performanceEvents.end(interval, outcome: .failed)
            throw error
        }
    }

    /// 1回のpolling tickを方式Bで取得・保存して表示用sampleを返します。
    ///
    /// 責務: 1 batchの物理観測を原子保存済みRaw証拠と表示用sampleへ変換します。
    /// - Parameter input: stable ordinalとpolicy tickを持つbatch入力。
    /// - Returns: 同じ物理応答から生成した表示用sample。
    /// - Throws: start未完了、stale世代、入力不正、または永続化失敗。
    func acquire(_ input: LiveTelemetryAcquisitionBatchInput) async throws -> [OBDPIDSample] {
        guard let permission, permission.generation == input.generation else {
            let staleInterval = performanceEvents.begin(
                .staleBatchRejection,
                context: AcquisitionPerformanceContext(
                    generation: input.generation,
                    batchOrdinal: input.batchOrdinal,
                    policyTick: input.policyTick,
                    scheduleDelayNanoseconds: input.scheduleDelayNanoseconds
                )
            )
            performanceEvents.end(staleInterval, outcome: .failed)
            throw PersistAcquisitionBatchError.inactiveGeneration
        }
        let interval = performanceEvents.begin(
            .batchAcquisition,
            context: AcquisitionPerformanceContext(
                generation: input.generation,
                batchOrdinal: input.batchOrdinal,
                policyTick: input.policyTick,
                scheduleDelayNanoseconds: input.scheduleDelayNanoseconds
            )
        )
        do {
            let result = try await persistBatch.executeWithSamples(
                PersistAcquisitionBatchInput(
                    permission: permission,
                    batchIdentity: try AcquisitionBatchIdentity(ordinal: input.batchOrdinal),
                    policyTick: input.policyTick,
                    startedAt: input.startedAt,
                    definitions: input.definitions,
                    endpoint: input.endpoint
                )
            )
            performanceEvents.end(interval, outcome: .succeeded)
            return result.samples
        } catch PersistAcquisitionBatchError.inactiveGeneration {
            performanceEvents.end(interval, outcome: .cancelled)
            throw PersistAcquisitionBatchError.inactiveGeneration
        } catch {
            performanceEvents.end(interval, outcome: .failed)
            throw error
        }
    }

    /// 指定世代からの新しい証拠作成を停止します。
    ///
    /// 責務: 1世代のmanifestとbatch orchestrationをstale状態へ遷移させます。
    /// - Parameter generation: 停止する取得世代。
    func cancel(generation: UInt) async {
        let interval = performanceEvents.begin(
            .generationCancellation,
            context: AcquisitionPerformanceContext(generation: generation)
        )
        await createManifest.cancel(generation: generation)
        await persistBatch.cancel(generation: generation)
        if permission?.generation == generation { permission = nil }
        performanceEvents.end(interval, outcome: .succeeded)
    }
}
