import Observation

/// 優先度付きPID継続取得をApplicationユースケースへ結び付けます。
@MainActor
@Observable
final class LiveTelemetryModel {
    /// Platformが描画する現在状態です。
    var state: LiveTelemetryState
    /// 検証済み主要PIDを数値化するユースケースです。
    @ObservationIgnored private let readMajorPIDs: ReadMajorOBDPIDsUseCase
    /// 車両別の対応PIDを再利用または初回探索するユースケースです。
    @ObservationIgnored private let loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase?
    /// PID更新対象と間引き周期を決める方針です。
    @ObservationIgnored private let pollingPolicy: OBDPIDPollingPolicy
    /// PID取得セッションが終了した原因をLoggingへ通知する処理です。
    @ObservationIgnored private let sessionDidEnd: @MainActor (ConnectionSessionEndReason) -> Void
    /// 取得できた累積走行距離をLoggingへ通知する処理です。
    @ObservationIgnored private let odometerDidChange: @MainActor (Double) -> Void
    /// 現在画面の表示有無から独立して動く取得タスクです。
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    /// 古い取得完了を新しい接続状態へ反映しないための世代です。
    @ObservationIgnored private var pollingGeneration: UInt = 0

    /// 初期状態、PID読取ユースケース、更新方針、終了通知先を固定します。
    ///
    /// 責務: PID表示状態を1件の読取ユースケースへ結び付けます。
    /// - Parameters:
    ///   - state: Platformへ公開する初期状態。
    ///   - readMajorPIDs: 主要PID読取と数値化を行うユースケース。
    ///   - loadVehicleCapabilities: 車両別対応PIDの再利用または初回探索を行うユースケース。
    ///   - pollingPolicy: PIDごとの更新優先度と間引き周期を決める方針。
    ///   - sessionDidEnd: PID取得終了原因をLoggingへ通知する処理。
    ///   - odometerDidChange: Service 01 PID A6の累積走行距離をLoggingへ通知する処理。
    init(
        state: LiveTelemetryState,
        readMajorPIDs: ReadMajorOBDPIDsUseCase,
        loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase? = nil,
        pollingPolicy: OBDPIDPollingPolicy,
        sessionDidEnd: @escaping @MainActor (ConnectionSessionEndReason) -> Void = { _ in },
        odometerDidChange: @escaping @MainActor (Double) -> Void = { _ in }
    ) {
        self.state = state
        self.readMajorPIDs = readMajorPIDs
        self.loadVehicleCapabilities = loadVehicleCapabilities
        self.pollingPolicy = pollingPolicy
        self.sessionDidEnd = sessionDidEnd
        self.odometerDidChange = odometerDidChange
    }

    /// 空の表示状態と既定更新方針を使って生成します。
    ///
    /// 責務: 1件のPID読取ユースケースを標準的なリアルタイム取得モデルへ変換します。
    /// - Parameters:
    ///   - readMajorPIDs: PID読取と数値化を行うユースケース。
    ///   - loadVehicleCapabilities: 車両別対応PIDの再利用または初回探索を行うユースケース。
    ///   - sessionDidEnd: PID取得終了原因をLoggingへ通知する処理。
    ///   - odometerDidChange: Service 01 PID A6の累積走行距離をLoggingへ通知する処理。
    convenience init(
        readMajorPIDs: ReadMajorOBDPIDsUseCase,
        loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase? = nil,
        sessionDidEnd: @escaping @MainActor (ConnectionSessionEndReason) -> Void = { _ in },
        odometerDidChange: @escaping @MainActor (Double) -> Void = { _ in }
    ) {
        self.init(
            state: LiveTelemetryState(),
            readMajorPIDs: readMajorPIDs,
            loadVehicleCapabilities: loadVehicleCapabilities,
            pollingPolicy: OBDPIDPollingPolicy(),
            sessionDidEnd: sessionDidEnd,
            odometerDidChange: odometerDidChange
        )
    }

    /// 型付き操作をPID読取ワークフローへ変換します。
    ///
    /// 責務: 1件のLiveTelemetry操作を新規読取または再読取に振り分けます。
    /// - Parameter action: Platformから通知された型付き操作。
    func send(_ action: LiveTelemetryAction) {
        switch action {
        case let .startRequested(endpoint, vehicleID):
            start(using: endpoint, vehicleID: vehicleID)
        case .retryRequested:
            if let endpoint = state.endpoint, let vehicleID = state.vehicleID { start(using: endpoint, vehicleID: vehicleID) }
        case .stopRequested:
            stop()
        }
    }

    /// 指定OBD終端からPID継続取得を開始します。
    ///
    /// 責務: 以前の取得を無効化して最新接続の継続取得タスクを開始します。
    /// - Parameters:
    ///   - endpoint: OBDアダプターの物理終端。
    ///   - vehicleID: 対応PID設定を参照する車両ID。
    private func start(using endpoint: OBDConnectionEndpoint, vehicleID: VehicleID) {
        let previousTask = pollingTask
        previousTask?.cancel()
        pollingGeneration &+= 1
        let generation = pollingGeneration
        state.endpoint = endpoint
        state.vehicleID = vehicleID
        state.phase = .reading
        state.failureKey = nil
        state.samples = []
        state.supportedPIDCount = 0
        pollingTask = Task { [weak self] in
            _ = await previousTask?.value
            await self?.poll(using: endpoint, vehicleID: vehicleID, generation: generation)
        }
    }

    /// 現在のPID継続取得を無効化します。
    ///
    /// 責務: 現在世代の取得タスクを取消して待機状態へ戻します。
    private func stop() {
        let shouldNotifySessionEnd = pollingTask != nil || state.isConnectionActive
        let previousTask = pollingTask
        previousTask?.cancel()
        pollingTask = nil
        pollingGeneration &+= 1
        let generation = pollingGeneration
        state.phase = .stopping
        state.failureKey = nil
        Task { [weak self, readMajorPIDs] in
            _ = await previousTask?.value
            await readMajorPIDs.endSession()
            guard let self, self.pollingGeneration == generation else { return }
            self.state.phase = .idle
            if shouldNotifySessionEnd { self.sessionDidEnd(.userDisconnected) }
        }
    }

    /// 初回全件探索後に優先度付きPID更新を繰り返します。
    ///
    /// 責務: 1件の接続終端を応答済みPIDの継続的な最新値へ変換します。
    /// - Parameters:
    ///   - endpoint: OBDアダプターの物理終端。
    ///   - vehicleID: 対応PID設定を参照する車両ID。
    ///   - generation: この取得開始時の世代。
    private func poll(using endpoint: OBDConnectionEndpoint, vehicleID: VehicleID, generation: UInt) async {
        do {
            let definitions: [OBDPIDDefinition]
            if let loadVehicleCapabilities {
                let capabilities = try await loadVehicleCapabilities.execute(vehicleID: vehicleID, endpoint: endpoint)
                definitions = try readMajorPIDs.loadDefinitions(for: capabilities)
            } else {
                definitions = try readMajorPIDs.loadDefinitions()
            }
            let initialSamples = try await readMajorPIDs.execute(definitions: definitions, using: endpoint)
            try Task.checkCancellation()
            guard pollingGeneration == generation, !initialSamples.isEmpty else {
                if initialSamples.isEmpty { throw OBDPIDTelemetryError.noVehicleResponse }
                await readMajorPIDs.endSession()
                return
            }
            let supportedRequests = Set(initialSamples.map(\.request))
            let supportedDefinitions = definitions.filter {
                supportedRequests.contains(OBDPIDRequest(service: $0.service, pid: $0.pid))
            }
            state.samples = ordered(initialSamples, definitions: supportedDefinitions)
            notifyOdometer(from: initialSamples)
            state.supportedPIDCount = supportedDefinitions.count
            state.phase = .loaded
            var tick: UInt = 1
            while !Task.isCancelled, pollingGeneration == generation {
                try await Task.sleep(for: .milliseconds(250))
                let batch = pollingPolicy.definitionsToPoll(from: supportedDefinitions, tick: tick)
                let samples = try await readMajorPIDs.execute(definitions: batch, using: endpoint)
                try Task.checkCancellation()
                guard !samples.isEmpty else { throw OBDPIDTelemetryError.noVehicleResponse }
                guard pollingGeneration == generation else {
                    await readMajorPIDs.endSession()
                    return
                }
                merge(samples, definitions: supportedDefinitions)
                tick &+= 1
            }
            await readMajorPIDs.endSession()
        } catch OBDPIDTelemetryError.definitionCatalogUnavailable {
            await readMajorPIDs.endSession()
            guard pollingGeneration == generation else { return }
            state.phase = .failed
            state.failureKey = "telemetry.error.pid_catalog_unavailable"
            sessionDidEnd(.acquisitionFailed)
        } catch OBDPIDTelemetryError.unavailable {
            await readMajorPIDs.endSession()
            guard pollingGeneration == generation else { return }
            state.phase = .failed
            state.failureKey = "telemetry.error.unavailable"
            sessionDidEnd(.acquisitionFailed)
        } catch OBDPIDTelemetryError.noVehicleResponse {
            await readMajorPIDs.endSession()
            guard pollingGeneration == generation else { return }
            pollingTask = nil
            state.phase = .idle
            state.failureKey = "telemetry.disconnected.no_response"
            sessionDidEnd(.vehicleNoResponse)
        } catch OBDPIDTelemetryError.connectionLost {
            await readMajorPIDs.endSession()
            guard pollingGeneration == generation else { return }
            pollingTask = nil
            state.phase = .idle
            state.failureKey = "telemetry.disconnected.connection_lost"
            sessionDidEnd(.connectionLost)
        } catch is CancellationError {
            await readMajorPIDs.endSession()
            return
        } catch {
            await readMajorPIDs.endSession()
            guard pollingGeneration == generation else { return }
            state.phase = .failed
            state.failureKey = "telemetry.error.read_failed"
            sessionDidEnd(.acquisitionFailed)
        }
    }

    /// 新しい観測をPIDごとの最新値へ統合します。
    ///
    /// 責務: 1回分の観測値で同一PIDの現在表示値だけを置き換えます。
    /// - Parameters:
    ///   - samples: 今回更新できた観測値。
    ///   - definitions: 表示順を決定する対応済み定義。
    private func merge(_ samples: [OBDPIDSample], definitions: [OBDPIDDefinition]) {
        var latest = Dictionary(uniqueKeysWithValues: state.samples.map { ($0.request, $0) })
        for sample in samples { latest[sample.request] = sample }
        state.samples = ordered(Array(latest.values), definitions: definitions)
        notifyOdometer(from: samples)
    }

    /// PID観測一覧に含まれる累積走行距離をLoggingへ通知します。
    ///
    /// 責務: 1回分のPID観測からService 01 PID A6だけを累積走行距離通知へ変換します。
    /// - Parameter samples: 今回取得できた数値化済みPID観測。
    private func notifyOdometer(from samples: [OBDPIDSample]) {
        let request = OBDPIDRequest(service: 0x01, pid: 0xA6)
        guard let odometer = samples.first(where: { $0.request == request })?.value else { return }
        odometerDidChange(odometer)
    }

    /// 観測値を優先度付き定義順へ並べます。
    ///
    /// 責務: PID観測一覧を高優先PIDが先頭になる安定表示順へ変換します。
    /// - Parameters:
    ///   - samples: 並べ替えるPID観測。
    ///   - definitions: 対応済みPID定義。
    /// - Returns: 高優先PIDを先頭にした観測一覧。
    private func ordered(_ samples: [OBDPIDSample], definitions: [OBDPIDDefinition]) -> [OBDPIDSample] {
        let order = pollingPolicy.definitionsToPoll(from: definitions, tick: 0).map {
            OBDPIDRequest(service: $0.service, pid: $0.pid)
        }
        let ranks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return samples.sorted { ranks[$0.request, default: .max] < ranks[$1.request, default: .max] }
    }
}
