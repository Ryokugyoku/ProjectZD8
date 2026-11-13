import Foundation
import os

/// 開始済みのセッションに対してPIDを周期的に要求し、Rawサンプルを保存して値を配信します。
///
/// 1セッションにつき1回だけ `run()` できます。`run()` はリンクを必ず1回閉じ、セッションを必ず1回終了します。
actor AcquisitionEngine {
    /// ティックの最短周期(マイクロ秒)です。
    static let minimumTickMicroseconds: Int64 = 100_000
    /// 高頻度PIDが無応答のまま続いたら車両無応答とみなすティック数です。
    static let noResponseTickLimit = 20

    /// 取得中の出来事です。`run()` の終了時に完了します。
    nonisolated let events: AsyncStream<AcquisitionEvent>

    private let eventContinuation: AsyncStream<AcquisitionEvent>.Continuation
    private let stopFlag = OSAllocatedUnfairLock(initialState: false)
    private let link: any OBDLink
    private let session: DriveSession
    private let pids: [SessionPID]
    private let vehicleModelCode: String?
    private let repository: any SessionRepository
    private let clock: any AcquisitionClock
    private let now: @Sendable () -> Date
    private let policy: AcquisitionPollingPolicy
    private let minimumTickMicroseconds: Int64
    private let noResponseTickLimit: Int
    private let decoder = SessionPIDDecoder()

    private var hasRun = false
    private var origin: Int64 = 0
    private var nextSequence: Int64 = 0
    private var sampleCount = 0
    private var respondedCount = 0
    private var distance = DistanceTracker()

    /// 責務: 取得に必要な依存と固定済みの取得条件を受け取ります。
    /// - Parameters:
    ///   - link: 初期化済みで開いているリンク。`run()` の終了時に閉じます。
    ///   - session: `SessionRepository.begin` 済みのセッション。
    ///   - pids: セッションに固定した取得条件。
    init(
        link: any OBDLink,
        session: DriveSession,
        pids: [SessionPID],
        vehicleModelCode: String?,
        repository: any SessionRepository,
        clock: any AcquisitionClock,
        now: @escaping @Sendable () -> Date,
        policy: AcquisitionPollingPolicy = AcquisitionPollingPolicy(),
        minimumTickMicroseconds: Int64 = AcquisitionEngine.minimumTickMicroseconds,
        noResponseTickLimit: Int = AcquisitionEngine.noResponseTickLimit
    ) {
        let (stream, continuation) = AsyncStream<AcquisitionEvent>.makeStream()
        self.events = stream
        self.eventContinuation = continuation
        self.link = link
        self.session = session
        self.pids = pids
        self.vehicleModelCode = vehicleModelCode
        self.repository = repository
        self.clock = clock
        self.now = now
        self.policy = policy
        self.minimumTickMicroseconds = minimumTickMicroseconds
        self.noResponseTickLimit = noResponseTickLimit
    }

    /// 責務: 停止を要求します。実行中のティックが終わった後に `userStopped` で終了します。
    nonisolated func requestStop() {
        stopFlag.withLock { $0 = true }
    }

    /// 責務: 終了条件に達するまで取得を続け、リンクを閉じ、セッションを終了して返します。
    /// - Throws: 実行済みなら `alreadyRun`、終了状態を保存できなければ `finishFailed`。
    func run() async throws -> DriveSession {
        guard !hasRun else { throw AcquisitionEngineError.alreadyRun }
        hasRun = true
        origin = clock.nowMicroseconds()
        eventContinuation.yield(.started(.init(session: session, pids: pids, vehicleModelCode: vehicleModelCode)))
        let reason = await acquire()
        await link.close()
        do {
            let finished = try await repository.finish(session.id, at: now(), reason: reason)
            eventContinuation.yield(.ended(finished))
            eventContinuation.finish()
            return finished
        } catch {
            eventContinuation.finish()
            throw AcquisitionEngineError.finishFailed(reason)
        }
    }

    /// 責務: 終了条件に達するまでティックを繰り返し、終了理由を返します。
    private func acquire() async -> SessionEndReason {
        var tick = 0
        var silentTicks = 0
        while true {
            if stopFlag.withLock({ $0 }) || Task.isCancelled { return .userStopped }
            let tickStart = clock.nowMicroseconds()
            let requested = policy.pidsToPoll(tick: tick, from: pids)
            var samples: [SessionSample] = []
            var readings: [AcquisitionEvent.TickReading] = []
            var linkFailure: SessionEndReason?
            for pid in requested {
                do {
                    let result = try await link.query(pid.request, header: pid.header)
                    samples.append(SessionSample(
                        sequence: nextSequence,
                        tick: tick,
                        elapsedMicroseconds: clock.nowMicroseconds() - origin,
                        request: pid.request,
                        outcome: result.outcome,
                        payload: Data(result.payload)
                    ))
                    nextSequence += 1
                    readings.append(.init(request: pid.request, reading: decoder.decode(pid, result: result)))
                } catch is CancellationError {
                    linkFailure = .userStopped
                    break
                } catch {
                    linkFailure = .connectionLost
                    break
                }
            }
            if !samples.isEmpty {
                do { try await repository.append(samples, to: session.id) } catch { return .acquisitionFailed }
                sampleCount += samples.count
                respondedCount += samples.filter { $0.outcome == .responded }.count
            }
            if let linkFailure { return linkFailure }
            for entry in readings {
                guard case .value(let kilometers) = entry.reading else { continue }
                if let update = distance.record(kilometers, for: entry.request) {
                    do {
                        try await repository.recordDistance(
                            startKilometers: update.startKilometers,
                            endKilometers: update.endKilometers,
                            source: update.source,
                            for: session.id
                        )
                    } catch { return .acquisitionFailed }
                }
            }
            eventContinuation.yield(.tick(.init(
                tick: tick,
                elapsedMicroseconds: clock.nowMicroseconds() - origin,
                readings: readings,
                sampleCount: sampleCount,
                respondedCount: respondedCount,
                distanceKilometers: distance.current?.distanceKilometers
            )))
            silentTicks = isSilent(requested: requested, samples: samples) ? silentTicks + 1 : 0
            if silentTicks >= noResponseTickLimit { return .vehicleNoResponse }
            tick += 1
            let spent = clock.nowMicroseconds() - tickStart
            if spent < minimumTickMicroseconds { await clock.sleep(microseconds: minimumTickMicroseconds - spent) }
        }
    }

    /// 責務: 高頻度グループ(無ければ要求全体)の全PIDが無応答だったティックかを判定します。
    private func isSilent(requested: [SessionPID], samples: [SessionSample]) -> Bool {
        let fast = requested.filter(\.isFastGroup)
        let basis = Set((fast.isEmpty ? requested : fast).map(\.request))
        return !samples.contains { basis.contains($0.request) && $0.outcome == .responded }
    }
}
