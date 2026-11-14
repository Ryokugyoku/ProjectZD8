import Foundation
import Observation

/// 応答駆動の取得ループの開始・停止を指示し、その出来事を購読して表示状態へ反映します。
@MainActor
@Observable
final class LiveTelemetryModel {
    /// Platformが描画する現在状態です。
    var state: LiveTelemetryState
    /// 取得開始前に取得対象のPID定義とcapabilityを確定するユースケースです。
    @ObservationIgnored private let prepareAcquisition: PrepareLiveTelemetryAcquisitionUseCase
    /// PIDを1件ずつ送る応答駆動の取得ループです。
    @ObservationIgnored private let acquisitionLoop: LiveTelemetryAcquisitionLoop
    /// 表示順を決める方針です。
    @ObservationIgnored private let pollingPolicy: OBDPIDPollingPolicy
    /// 表示更新の間引きを測る単調時計です。
    @ObservationIgnored private let clock: any MonotonicClockPort
    /// PID取得セッションが終了した原因と終了時刻をLoggingへ通知する処理です。終了時刻が `nil` なら処理した時刻を使います。
    @ObservationIgnored private let sessionDidEnd: @MainActor (ConnectionSessionEndReason, Date?) -> Void
    /// 取得できた取得元付き累積距離をLoggingへ通知する処理です。
    @ObservationIgnored private let distanceDidChange: @MainActor (ConnectionSessionDistanceObservation) -> Void
    /// 車両接続中のシステムスリープ抑止を切り替えるOS境界です。
    @ObservationIgnored private let systemSleepInhibitor: (any VehicleConnectionSystemSleepInhibiting)?
    /// 取得対象の確定と取得ループの購読を行うタスクです。
    @ObservationIgnored private var acquisitionTask: Task<Void, Never>?
    /// 古い取得の出来事を新しい接続状態へ反映しないための世代です。
    @ObservationIgnored private var generation: UInt = 0
    /// 表示更新の間引き状態です。
    @ObservationIgnored private var refreshThrottle = LiveTelemetryDisplayRefreshThrottle()
    /// 初回周回で確定した取得対象です。表示順の基準に使います。
    @ObservationIgnored private var supportedDefinitions: [OBDPIDDefinition] = []

    /// 初期状態、取得対象の確定、取得ループ、通知先を固定します。
    ///
    /// 責務: 表示状態を取得ループの購読者として結び付けます。
    /// - Parameters:
    ///   - state: Platformへ公開する初期状態。
    ///   - prepareAcquisition: 取得対象のPID定義とcapabilityを確定するユースケース。
    ///   - acquisitionLoop: PIDを1件ずつ送る応答駆動の取得ループ。
    ///   - pollingPolicy: 表示順を決める方針。
    ///   - clock: 表示更新の間引きを測る単調時計。
    ///   - sessionDidEnd: PID取得終了原因と終了時刻(猶予切れでは最後に受信した時刻、それ以外は `nil`)をLoggingへ通知する処理。
    ///   - distanceDidChange: 車種専用PID、Service 01 PID A6、またはPID 31の累積距離をLoggingへ通知する処理。
    ///   - systemSleepInhibitor: 車両接続中だけシステムスリープを抑止する境界。
    init(
        state: LiveTelemetryState,
        prepareAcquisition: PrepareLiveTelemetryAcquisitionUseCase,
        acquisitionLoop: LiveTelemetryAcquisitionLoop,
        pollingPolicy: OBDPIDPollingPolicy = OBDPIDPollingPolicy(),
        clock: any MonotonicClockPort,
        sessionDidEnd: @escaping @MainActor (ConnectionSessionEndReason, Date?) -> Void = { _, _ in },
        distanceDidChange: @escaping @MainActor (ConnectionSessionDistanceObservation) -> Void = { _ in },
        systemSleepInhibitor: (any VehicleConnectionSystemSleepInhibiting)? = nil
    ) {
        self.state = state
        self.prepareAcquisition = prepareAcquisition
        self.acquisitionLoop = acquisitionLoop
        self.pollingPolicy = pollingPolicy
        self.clock = clock
        self.sessionDidEnd = sessionDidEnd
        self.distanceDidChange = distanceDidChange
        self.systemSleepInhibitor = systemSleepInhibitor
    }

    /// 型付き操作を取得ワークフローへ変換します。
    ///
    /// 責務: 1件のLiveTelemetry操作を開始・再開・停止・アプリ状態とリンク状態の通知へ振り分けます。
    /// - Parameter action: Platformから通知された型付き操作。
    func send(_ action: LiveTelemetryAction) {
        switch action {
        case let .startRequested(endpoint, vehicle):
            start(using: endpoint, vehicle: vehicle)
        case .retryRequested:
            if let endpoint = state.endpoint, let vehicle = state.vehicle {
                start(using: endpoint, vehicle: vehicle)
            }
        case .stopRequested:
            stop()
        case .backgroundTransitionOccurred:
            Task { [acquisitionLoop] in
                await acquisitionLoop.flush(.backgroundTransition)
                await acquisitionLoop.notify(.backgroundEntered)
            }
        case .foregroundTransitionOccurred:
            Task { [acquisitionLoop] in await acquisitionLoop.notify(.foregroundEntered) }
        case let .adapterLinkAvailabilityChanged(isAvailable):
            Task { [acquisitionLoop] in await acquisitionLoop.notify(isAvailable ? .linkRestored : .linkLost) }
        }
    }

    /// 指定OBD終端からPID継続取得を開始します。
    ///
    /// 責務: 以前の取得の購読を無効化し、最新接続のスリープ抑止と取得ループの購読を開始します。
    /// - Parameters:
    ///   - endpoint: OBDアダプターの物理終端。
    ///   - vehicle: 登録済み車両(ID・型式コード)または未登録。
    private func start(using endpoint: OBDConnectionEndpoint, vehicle: LiveTelemetryVehicleContext) {
        let previousTask = acquisitionTask
        previousTask?.cancel()
        generation &+= 1
        let generation = generation
        state.endpoint = endpoint
        state.vehicle = vehicle
        state.phase = .reading
        state.failureKey = nil
        state.pauseStatus = nil
        state.samples = []
        state.supportedPIDCount = 0
        refreshThrottle = LiveTelemetryDisplayRefreshThrottle()
        supportedDefinitions = []
        systemSleepInhibitor?.setVehicleConnectionActive(true)
        acquisitionTask = Task { [weak self] in
            _ = await previousTask?.value
            await self?.acquire(using: endpoint, vehicle: vehicle, generation: generation)
        }
    }

    /// 現在のPID継続取得を止めます。
    ///
    /// 責務: 購読を無効化して取得ループを止め、終了を待ってスリープ抑止解除済みの待機状態へ戻します。
    private func stop() {
        let shouldNotifySessionEnd = acquisitionTask != nil || state.isConnectionActive
        let previousTask = acquisitionTask
        previousTask?.cancel()
        acquisitionTask = nil
        generation &+= 1
        let generation = generation
        state.phase = .stopping
        state.failureKey = nil
        state.pauseStatus = nil
        Task { [weak self, acquisitionLoop, prepareAcquisition] in
            _ = await previousTask?.value
            let termination = await acquisitionLoop.stop()
            await prepareAcquisition.endSession()
            guard let self, self.generation == generation else { return }
            self.finishStop(termination: termination, notifiesSessionEnd: shouldNotifySessionEnd)
        }
    }

    /// 停止の完了を表示状態へ反映します。
    ///
    /// 責務: 停止時の記録失敗を成功扱いせず、待機状態と終了通知へ変換します。
    /// - Parameters:
    ///   - termination: 取得ループの終了理由。動いていなかった場合は `nil`。
    ///   - notifiesSessionEnd: Loggingへ終了を通知するかどうか。
    private func finishStop(termination: LiveTelemetryAcquisitionTermination?, notifiesSessionEnd: Bool) {
        applyPendingSamples(force: true)
        systemSleepInhibitor?.setVehicleConnectionActive(false)
        if termination == .recordingFailed {
            state.phase = .failed
            state.failureKey = "telemetry.error.read_failed"
            sessionDidEnd(.acquisitionFailed, nil)
            return
        }
        state.phase = .idle
        if notifiesSessionEnd { sessionDidEnd(.userDisconnected, nil) }
    }

    /// 取得対象を確定して取得ループを始め、その出来事を購読します。
    ///
    /// 責務: 1世代の取得準備と出来事の購読を行い、古い世代の出来事を捨てます。
    /// - Parameters:
    ///   - endpoint: OBDアダプターの物理終端。
    ///   - vehicle: 登録済み車両(ID・型式コード)または未登録。
    ///   - generation: この取得開始時の世代。
    private func acquire(
        using endpoint: OBDConnectionEndpoint,
        vehicle: LiveTelemetryVehicleContext,
        generation: UInt
    ) async {
        let prepared: (definitions: [OBDPIDDefinition], capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput])
        do {
            prepared = try await prepareAcquisition.execute(vehicle: vehicle, endpoint: endpoint)
        } catch {
            await prepareAcquisition.endSession()
            guard self.generation == generation, !(error is CancellationError) else { return }
            handlePreparationFailure(error)
            return
        }
        guard self.generation == generation, !Task.isCancelled else { return }
        let events = await acquisitionLoop.start(
            LiveTelemetryAcquisitionLoopInput(
                generation: generation,
                definitions: prepared.definitions,
                capabilities: prepared.capabilities,
                endpoint: endpoint
            )
        )
        for await event in events {
            guard self.generation == generation else { return }
            apply(event)
        }
    }

    /// 取得ループの出来事を表示状態へ反映します。
    ///
    /// 責務: 観測は間引いて反映し、取得対象の確定・段階の変化・終了は間引かずに反映します。
    /// - Parameter event: 取得ループが流した出来事。
    private func apply(_ event: LiveTelemetryAcquisitionEvent) {
        switch event {
        case let .targetsConfirmed(definitions):
            supportedDefinitions = definitions
            state.supportedPIDCount = definitions.count
            state.phase = .loaded
            applyPendingSamples(force: true)
        case let .sampleDecoded(sample):
            refreshThrottle.hold(sample)
            if state.phase == .loaded { applyPendingSamples(force: false) }
        case let .phaseChanged(acquisitionPhase):
            applyPhase(acquisitionPhase)
        case let .ended(termination):
            applyPendingSamples(force: true)
            handleTermination(termination)
        }
    }

    /// 取得ループの段階を表示状態へ反映します。
    ///
    /// 責務: 回復中・一時停止中を `paused` へ、取得中への復帰を確定前なら `reading`、確定後なら `loaded` へ変換します。
    /// - Parameter acquisitionPhase: 取得ループが報告した段階。
    private func applyPhase(_ acquisitionPhase: LiveTelemetryAcquisitionPhase) {
        guard state.phase != .stopping else { return }
        if let pauseStatus = LiveTelemetryPauseStatus(acquisitionPhase) {
            applyPendingSamples(force: true)
            state.pauseStatus = pauseStatus
            state.phase = .paused
            return
        }
        state.pauseStatus = nil
        state.phase = supportedDefinitions.isEmpty ? .reading : .loaded
    }

    /// 保持中の観測をPIDごとの最新値へまとめて反映します。
    ///
    /// 責務: 間引き判定を通った観測、または強制時の全観測で同一PIDの表示値を置き換えます。
    /// - Parameter force: 間引き間隔を待たずに反映するかどうか。
    private func applyPendingSamples(force: Bool) {
        let now = clock.nowNanoseconds()
        let samples = force ? refreshThrottle.takeAll(nowNanoseconds: now) : refreshThrottle.takeIfDue(nowNanoseconds: now)
        guard let samples, !samples.isEmpty else { return }
        var latest = Dictionary(state.samples.map { ($0.request, $0) }, uniquingKeysWith: { _, last in last })
        for sample in samples { latest[sample.request] = sample }
        state.samples = ordered(Array(latest.values))
        notifyDistance(from: samples)
    }

    /// 取得ループの終了理由を表示状態と終了通知へ反映します。
    ///
    /// 責務: 停止以外の終了をスリープ抑止解除済みの終了状態とLogging通知へ変換します。
    /// 猶予切れでは最後に受信した時刻をセッションの終了時刻として通知します。
    /// - Parameter termination: 取得ループの終了理由。
    private func handleTermination(_ termination: LiveTelemetryAcquisitionTermination) {
        guard termination != .stopped else { return }
        acquisitionTask = nil
        state.pauseStatus = nil
        systemSleepInhibitor?.setVehicleConnectionActive(false)
        switch termination {
        case .stopped:
            return
        case .gracePeriodExpired(.responseStall, _):
            state.phase = .idle
            state.failureKey = "telemetry.disconnected.no_response"
        case .gracePeriodExpired(.linkLost, _):
            state.phase = .idle
            state.failureKey = "telemetry.disconnected.connection_lost"
        case .recordingFailed:
            state.phase = .failed
            state.failureKey = "telemetry.error.read_failed"
        }
        sessionDidEnd(termination.sessionEndReason, termination.sessionEndedAt)
    }

    /// 取得対象を確定できなかった失敗を表示状態へ反映します。
    ///
    /// 責務: 1件の準備エラーをスリープ抑止解除済みの失敗状態とLogging通知へ変換します。
    /// - Parameter error: 取得対象の確定で送出されたエラー。
    private func handlePreparationFailure(_ error: Error) {
        systemSleepInhibitor?.setVehicleConnectionActive(false)
        switch error {
        case OBDPIDTelemetryError.definitionCatalogUnavailable:
            state.phase = .failed
            state.failureKey = "telemetry.error.pid_catalog_unavailable"
            sessionDidEnd(.acquisitionFailed, nil)
        case OBDPIDTelemetryError.unavailable:
            state.phase = .failed
            state.failureKey = "telemetry.error.unavailable"
            sessionDidEnd(.acquisitionFailed, nil)
        case OBDPIDTelemetryError.noVehicleResponse:
            acquisitionTask = nil
            state.phase = .idle
            state.failureKey = "telemetry.disconnected.no_response"
            sessionDidEnd(.vehicleNoResponse, nil)
        case OBDPIDTelemetryError.connectionLost:
            acquisitionTask = nil
            state.phase = .idle
            state.failureKey = "telemetry.disconnected.connection_lost"
            sessionDidEnd(.connectionLost, nil)
        default:
            state.phase = .failed
            state.failureKey = "telemetry.error.read_failed"
            sessionDidEnd(.acquisitionFailed, nil)
        }
    }

    /// PID観測一覧から優先順位が最も高い累積距離をLoggingへ通知します。
    ///
    /// 責務: 1回分のPID観測を車種専用距離、A6、PID 31の優先順で取得元付き累積距離通知へ変換します。
    /// - Parameter samples: 今回反映した数値化済みPID観測。受信順に並びます。
    private func notifyDistance(from samples: [OBDPIDSample]) {
        let candidates: [(OBDPIDRequest, ConnectionSessionDistanceSource)] = [
            (OBDPIDRequest(service: 0x21, pid: 0x02), .vehicleSpecificOdometer),
            (OBDPIDRequest(service: 0x01, pid: 0xA6), .odometer),
            (OBDPIDRequest(service: 0x01, pid: 0x31), .distanceSinceCodesCleared)
        ]
        guard let candidate = candidates.compactMap({ request, source in
            samples.last(where: { $0.request == request }).map {
                ConnectionSessionDistanceObservation(
                    source: source,
                    kilometers: $0.value,
                    vehicleModelCode: $0.vehicleModelCode
                )
            }
        }).first else { return }
        distanceDidChange(candidate)
    }

    /// 観測値を優先度付き定義順へ並べます。
    ///
    /// 責務: PID観測一覧を高優先PIDが先頭になる安定表示順へ変換します。
    /// - Parameter samples: 並べ替えるPID観測。
    /// - Returns: 高優先PIDを先頭にした観測一覧。
    private func ordered(_ samples: [OBDPIDSample]) -> [OBDPIDSample] {
        let order = pollingPolicy.definitionsToPoll(from: supportedDefinitions, tick: 0).map {
            OBDPIDRequest(service: $0.service, pid: $0.pid)
        }
        let ranks = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return samples.sorted { ranks[$0.request, default: .max] < ranks[$1.request, default: .max] }
    }
}
