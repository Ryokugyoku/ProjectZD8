import Foundation
import Observation

/// アダプター接続から車両特定・取得条件の準備・記録・終了までの流れを管理します。
@MainActor
@Observable
final class DriveSessionModel {
    /// 画面が描画する状態です。
    private(set) var state = DriveSessionState()

    @ObservationIgnored private let linkPort: any OBDLinkPort
    @ObservationIgnored private let vehicles: any VehicleRepository
    @ObservationIgnored private let sessions: any SessionRepository
    @ObservationIgnored private let preparePIDs: PrepareSessionPIDsUseCase
    @ObservationIgnored private let environment: any AcquisitionEnvironmentPort
    @ObservationIgnored private let sleepInhibitor: any SleepInhibitingPort
    @ObservationIgnored private let events: any AcquisitionEventPublishing
    @ObservationIgnored private let clock: any AcquisitionClock
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let onSessionEnded: @MainActor (DriveSession) -> Void

    @ObservationIgnored private var registrationContinuation: CheckedContinuation<String?, Never>?
    @ObservationIgnored private var cancelRequested = false
    @ObservationIgnored private var engine: AcquisitionEngine?

    /// 責務: 流れに必要な依存を受け取ります。
    /// - Parameters:
    ///   - events: 取得の出来事の配信先(リアルタイム表示など)。
    ///   - onSessionEnded: セッションが終了した時と、起動時に未終了セッションを閉じた時に呼ばれます。
    init(
        linkPort: any OBDLinkPort,
        vehicles: any VehicleRepository,
        sessions: any SessionRepository,
        preparePIDs: PrepareSessionPIDsUseCase,
        environment: any AcquisitionEnvironmentPort,
        sleepInhibitor: any SleepInhibitingPort,
        events: any AcquisitionEventPublishing,
        clock: any AcquisitionClock,
        now: @escaping @Sendable () -> Date,
        onSessionEnded: @escaping @MainActor (DriveSession) -> Void
    ) {
        self.linkPort = linkPort
        self.vehicles = vehicles
        self.sessions = sessions
        self.preparePIDs = preparePIDs
        self.environment = environment
        self.sleepInhibitor = sleepInhibitor
        self.events = events
        self.clock = clock
        self.now = now
        self.onSessionEnded = onSessionEnded
    }

    /// 責務: 操作を状態遷移へ変換します。
    func send(_ action: DriveSessionAction) {
        switch action {
        case .connectRequested(let adapter):
            guard state.phase.isIdle else { return }
            state.failure = nil
            state.lastEndedSession = nil
            cancelRequested = false
            state.adapter = adapter
            state.phase = .connecting
            Task { await self.runWorkflow(adapter: adapter) }
        case .registrationSubmitted(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard case .awaitingVehicleRegistration = state.phase, !trimmed.isEmpty else { return }
            resumeRegistration(with: trimmed)
        case .registrationCancelled:
            guard case .awaitingVehicleRegistration = state.phase else { return }
            resumeRegistration(with: nil)
        case .stopRequested:
            requestStop()
        case .failureDismissed:
            state.failure = nil
        case .appLaunched:
            Task { await self.finishUnfinishedSessions() }
        }
    }

    /// 責務: 段階に応じて停止を要求します。記録中はエンジンへ、それ以前は流れの中断点で止めます。
    private func requestStop() {
        switch state.phase {
        case .idle, .stopping:
            return
        case .recording:
            state.phase = .stopping
            engine?.requestStop()
        case .awaitingVehicleRegistration:
            cancelRequested = true
            state.phase = .stopping
            resumeRegistration(with: nil)
        case .connecting, .identifying, .preparing:
            cancelRequested = true
            state.phase = .stopping
        }
    }

    /// 責務: 待機中の車両登録を入力値(取りやめは `nil`)で再開します。
    private func resumeRegistration(with name: String?) {
        let continuation = registrationContinuation
        registrationContinuation = nil
        continuation?.resume(returning: name)
    }

    /// 責務: 前回起動で閉じられなかったセッションを終了し、終了したものを通知します。
    private func finishUnfinishedSessions() async {
        do {
            let ended = try await sessions.finishUnfinishedSessions(at: now())
            state.recoveredSessionCount = ended.count
            for session in ended { onSessionEnded(session) }
        } catch {
            state.failure = DriveSessionFailure(phase: .idle, kind: .store)
        }
    }

    /// 接続が成立し取得条件まで準備できた状態です。
    private struct Prepared {
        let link: any OBDLink
        let vehicle: Vehicle
        let session: DriveSession
        let pids: [SessionPID]
    }

    /// 流れの内部中断です。
    private enum WorkflowError: Error {
        case cancelled
        case vinMissing
    }

    /// 責務: 接続から記録終了までを順に進め、失敗は段階付きで状態へ反映します。
    private func runWorkflow(adapter: AdapterDescriptor) async {
        var stage = DriveSessionPhase.connecting
        var openedLink: (any OBDLink)?
        let prepared: Prepared
        do {
            let link = try await linkPort.open(adapter)
            openedLink = link
            try checkpoint()

            stage = .identifying
            state.phase = stage
            let identification = try await link.identify()
            try checkpoint()
            guard let vin = identification.vin?.trimmingCharacters(in: .whitespacesAndNewlines), !vin.isEmpty else {
                throw WorkflowError.vinMissing
            }

            let known = try await vehicles.vehicles().first { $0.vin.caseInsensitiveCompare(vin) == .orderedSame }
            try checkpoint()
            let vehicle: Vehicle
            if let known {
                vehicle = known
            } else {
                stage = .awaitingVehicleRegistration(identification)
                state.phase = stage
                let name = await withCheckedContinuation { registrationContinuation = $0 }
                guard let name else { throw WorkflowError.cancelled }
                try checkpoint()
                let timestamp = now()
                let registered = Vehicle(vin: vin, name: name, createdAt: timestamp, modifiedAt: timestamp)
                try await vehicles.save(registered)
                vehicle = registered
            }

            stage = .preparing
            state.phase = stage
            let pids = try await preparePIDs.execute(vehicle: vehicle, link: link)
            try checkpoint()
            let session = makeSession(vehicleID: vehicle.id, adapter: adapter)
            try await sessions.begin(session, pids: pids)
            prepared = Prepared(link: link, vehicle: vehicle, session: session, pids: pids)
        } catch {
            await openedLink?.close()
            if case WorkflowError.cancelled = error {
                returnToIdle()
            } else {
                returnToIdle(failure: DriveSessionFailure(phase: stage, kind: Self.failureKind(for: error)))
            }
            return
        }
        await record(prepared, adapter: adapter)
    }

    /// 責務: 停止要求が出ていれば流れを中断します。
    private func checkpoint() throws {
        if cancelRequested { throw WorkflowError.cancelled }
    }

    /// 責務: 取得エンジンを走らせ、終了後に状態を戻します。リンクはエンジンが閉じます。
    private func record(_ prepared: Prepared, adapter: AdapterDescriptor) async {
        let engine = AcquisitionEngine(
            link: prepared.link,
            session: prepared.session,
            pids: prepared.pids,
            vehicleModelCode: prepared.vehicle.modelCode,
            repository: sessions,
            clock: clock,
            now: now
        )
        self.engine = engine
        state.activeSession = ActiveSessionSummary(
            sessionID: prepared.session.id,
            vehicleName: prepared.vehicle.name,
            adapterName: prepared.session.adapterName,
            adapterTransport: prepared.session.adapterTransport,
            isDemo: prepared.session.isDemo,
            startedAt: prepared.session.startedAt,
            elapsedMicroseconds: 0,
            tickCount: 0,
            sampleCount: 0,
            respondedCount: 0,
            distanceKilometers: nil
        )
        sleepInhibitor.setInhibited(true)
        if cancelRequested {
            engine.requestStop()
        } else {
            state.phase = .recording
        }
        let pump = Task {
            for await event in engine.events { self.handle(event) }
        }
        var ended: DriveSession?
        var failure: DriveSessionFailure?
        do {
            ended = try await engine.run()
        } catch {
            failure = DriveSessionFailure(phase: .recording, kind: .store)
        }
        await pump.value
        sleepInhibitor.setInhibited(false)
        self.engine = nil
        returnToIdle(failure: failure, lastEnded: ended)
        if let ended { onSessionEnded(ended) }
    }

    /// 責務: 取得の出来事を要約へ反映し、配信先へ転送します。
    private func handle(_ event: AcquisitionEvent) {
        if case .tick(let tick) = event, var summary = state.activeSession {
            summary.elapsedMicroseconds = tick.elapsedMicroseconds
            summary.tickCount = tick.tick + 1
            summary.sampleCount = tick.sampleCount
            summary.respondedCount = tick.respondedCount
            summary.distanceKilometers = tick.distanceKilometers
            state.activeSession = summary
        }
        events.publish(event)
    }

    /// 責務: 流れを終えて待機状態へ戻します。
    private func returnToIdle(failure: DriveSessionFailure? = nil, lastEnded: DriveSession? = nil) {
        cancelRequested = false
        state.phase = .idle
        state.adapter = nil
        state.activeSession = nil
        state.failure = failure
        state.lastEndedSession = lastEnded
    }

    /// 責務: 接続先と実行環境から記録開始時のセッションを作ります。
    private func makeSession(vehicleID: VehicleID, adapter: AdapterDescriptor) -> DriveSession {
        let environment = environment.environment()
        let timestamp = now()
        return DriveSession(
            vehicleID: vehicleID,
            startedAt: timestamp,
            isDemo: adapter.transport == .demo,
            adapterName: adapter.displayName,
            adapterTransport: adapter.transport,
            platform: environment.platform,
            deviceID: environment.deviceID,
            deviceName: environment.deviceName,
            appVersion: environment.appVersion,
            appBuild: environment.appBuild,
            pollingPolicyVersion: AcquisitionPollingPolicy.version,
            modifiedAt: timestamp
        )
    }

    /// 責務: 投げられた失敗を表示用の種類へ分類します。
    private static func failureKind(for error: Error) -> DriveSessionFailure.Kind {
        switch error {
        case WorkflowError.vinMissing: .vinMissing
        case OBDLinkError.vinUnavailable: .vinMissing
        case let error as OBDLinkError: .link(error)
        case PrepareSessionPIDsUseCase.Failure.noPollablePIDs: .noPollablePIDs
        default: .store
        }
    }
}
