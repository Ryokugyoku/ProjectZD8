import Observation

/// 優先度付きPID継続取得をApplicationユースケースへ結び付けます。
@MainActor
@Observable
final class LiveTelemetryModel {
    /// Platformが描画する現在状態です。
    var state: LiveTelemetryState
    /// 検証済み主要PIDを数値化するユースケースです。
    @ObservationIgnored private let readMajorPIDs: ReadMajorOBDPIDsUseCase
    /// PID更新対象と間引き周期を決める方針です。
    @ObservationIgnored private let pollingPolicy: OBDPIDPollingPolicy
    /// 現在画面の表示有無から独立して動く取得タスクです。
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    /// 古い取得完了を新しい接続状態へ反映しないための世代です。
    @ObservationIgnored private var pollingGeneration: UInt = 0

    /// 初期状態、PID読取ユースケース、更新方針を固定します。
    ///
    /// 責務: PID表示状態を1件の読取ユースケースへ結び付けます。
    /// - Parameters:
    ///   - state: Platformへ公開する初期状態。
    ///   - readMajorPIDs: 主要PID読取と数値化を行うユースケース。
    ///   - pollingPolicy: PIDごとの更新優先度と間引き周期を決める方針。
    init(
        state: LiveTelemetryState,
        readMajorPIDs: ReadMajorOBDPIDsUseCase,
        pollingPolicy: OBDPIDPollingPolicy
    ) {
        self.state = state
        self.readMajorPIDs = readMajorPIDs
        self.pollingPolicy = pollingPolicy
    }

    /// 空の表示状態と既定更新方針を使って生成します。
    ///
    /// 責務: 1件のPID読取ユースケースを標準的なリアルタイム取得モデルへ変換します。
    /// - Parameter readMajorPIDs: PID読取と数値化を行うユースケース。
    convenience init(readMajorPIDs: ReadMajorOBDPIDsUseCase) {
        self.init(
            state: LiveTelemetryState(),
            readMajorPIDs: readMajorPIDs,
            pollingPolicy: OBDPIDPollingPolicy()
        )
    }

    /// 型付き操作をPID読取ワークフローへ変換します。
    ///
    /// 責務: 1件のLiveTelemetry操作を新規読取または再読取に振り分けます。
    /// - Parameter action: Platformから通知された型付き操作。
    func send(_ action: LiveTelemetryAction) {
        switch action {
        case let .startRequested(endpoint):
            start(using: endpoint)
        case .retryRequested:
            if let endpoint = state.endpoint { start(using: endpoint) }
        case .stopRequested:
            stop()
        }
    }

    /// 指定OBD終端からPID継続取得を開始します。
    ///
    /// 責務: 以前の取得を無効化して最新接続の継続取得タスクを開始します。
    /// - Parameter endpoint: OBDアダプターの物理終端。
    private func start(using endpoint: OBDConnectionEndpoint) {
        let previousTask = pollingTask
        previousTask?.cancel()
        pollingGeneration &+= 1
        let generation = pollingGeneration
        state.endpoint = endpoint
        state.phase = .reading
        state.failureKey = nil
        state.samples = []
        state.supportedPIDCount = 0
        pollingTask = Task { [weak self] in
            _ = await previousTask?.value
            await self?.poll(using: endpoint, generation: generation)
        }
    }

    /// 現在のPID継続取得を無効化します。
    ///
    /// 責務: 現在世代の取得タスクを取消して待機状態へ戻します。
    private func stop() {
        let previousTask = pollingTask
        previousTask?.cancel()
        pollingTask = nil
        pollingGeneration &+= 1
        state.phase = .idle
        Task { [readMajorPIDs] in
            _ = await previousTask?.value
            await readMajorPIDs.endSession()
        }
    }

    /// 初回全件探索後に優先度付きPID更新を繰り返します。
    ///
    /// 責務: 1件の接続終端を応答済みPIDの継続的な最新値へ変換します。
    /// - Parameters:
    ///   - endpoint: OBDアダプターの物理終端。
    ///   - generation: この取得開始時の世代。
    private func poll(using endpoint: OBDConnectionEndpoint, generation: UInt) async {
        do {
            let definitions = try readMajorPIDs.loadDefinitions()
            let initialSamples = try await readMajorPIDs.execute(definitions: definitions, using: endpoint)
            try Task.checkCancellation()
            guard pollingGeneration == generation, !initialSamples.isEmpty else {
                if initialSamples.isEmpty { throw OBDPIDTelemetryError.incompleteResponse }
                await readMajorPIDs.endSession()
                return
            }
            let supportedRequests = Set(initialSamples.map(\.request))
            let supportedDefinitions = definitions.filter {
                supportedRequests.contains(OBDPIDRequest(service: $0.service, pid: $0.pid))
            }
            state.samples = ordered(initialSamples, definitions: supportedDefinitions)
            state.supportedPIDCount = supportedDefinitions.count
            state.phase = .loaded
            var tick: UInt = 1
            while !Task.isCancelled, pollingGeneration == generation {
                try await Task.sleep(for: .milliseconds(250))
                let batch = pollingPolicy.definitionsToPoll(from: supportedDefinitions, tick: tick)
                let samples = try await readMajorPIDs.execute(definitions: batch, using: endpoint)
                try Task.checkCancellation()
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
        } catch OBDPIDTelemetryError.unavailable {
            await readMajorPIDs.endSession()
            guard pollingGeneration == generation else { return }
            state.phase = .failed
            state.failureKey = "telemetry.error.unavailable"
        } catch is CancellationError {
            await readMajorPIDs.endSession()
            return
        } catch {
            await readMajorPIDs.endSession()
            guard pollingGeneration == generation else { return }
            state.phase = .failed
            state.failureKey = "telemetry.error.read_failed"
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
