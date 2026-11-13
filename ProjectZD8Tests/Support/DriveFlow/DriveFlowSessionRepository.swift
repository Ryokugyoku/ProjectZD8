import Foundation
@testable import ProjectZD8

/// メモリ上の `SessionRepository` です。呼び出しを記録し、失敗を注入できます。
final class DriveFlowSessionRepository: SessionRepository, @unchecked Sendable {
    struct DistanceRecord: Equatable {
        let start: Double
        let end: Double
        let source: DistanceSource
    }

    struct Begun {
        let session: DriveSession
        let pids: [SessionPID]
    }

    struct Finish: Equatable {
        let id: SessionID
        let reason: SessionEndReason
    }

    private let lock = NSLock()
    private var _begun: [Begun] = []
    private var _appended: [[SessionSample]] = []
    private var _distances: [DistanceRecord] = []
    private var _finishes: [Finish] = []
    private var _unfinishedCalls = 0
    private var stored: [SessionID: DriveSession] = [:]
    private var failAppendAtCall: Int?
    private var failFinish = false
    private var failBegin = false
    private var failRecordDistance = false
    private var failFinishUnfinished = false
    private var unfinishedResult: [DriveSession] = []

    init() {}

    /// 責務: 失敗の注入と未終了セッションの戻り値を設定します。
    func configure(
        failAppendAtCall: Int? = nil, failFinish: Bool = false, failBegin: Bool = false,
        failRecordDistance: Bool = false, failFinishUnfinished: Bool = false, unfinishedResult: [DriveSession] = []
    ) {
        lock.withLock {
            self.failAppendAtCall = failAppendAtCall
            self.failFinish = failFinish
            self.failBegin = failBegin
            self.failRecordDistance = failRecordDistance
            self.failFinishUnfinished = failFinishUnfinished
            self.unfinishedResult = unfinishedResult
        }
    }

    /// 責務: `begin` を経ずにセッションを既存として登録します(エンジン単体のテスト用)。
    func seed(_ session: DriveSession) { lock.withLock { stored[session.id] = session } }

    var begun: [Begun] { lock.withLock { _begun } }
    var appended: [[SessionSample]] { lock.withLock { _appended } }
    var distances: [DistanceRecord] { lock.withLock { _distances } }
    var finishes: [Finish] { lock.withLock { _finishes } }
    var unfinishedCalls: Int { lock.withLock { _unfinishedCalls } }
    var allSamples: [SessionSample] { appended.flatMap { $0 } }

    func begin(_ session: DriveSession, pids: [SessionPID]) async throws {
        try lock.withLock {
            if failBegin { throw StoreError.ioFailure }
            _begun.append(Begun(session: session, pids: pids))
            stored[session.id] = session
        }
    }

    func append(_ samples: [SessionSample], to id: SessionID) async throws {
        try lock.withLock {
            if failAppendAtCall == _appended.count { throw StoreError.ioFailure }
            _appended.append(samples)
        }
    }

    func recordDistance(startKilometers: Double, endKilometers: Double, source: DistanceSource, for id: SessionID) async throws {
        try lock.withLock {
            if failRecordDistance { throw StoreError.ioFailure }
            _distances.append(DistanceRecord(start: startKilometers, end: endKilometers, source: source))
        }
    }

    func finish(_ id: SessionID, at date: Date, reason: SessionEndReason) async throws -> DriveSession {
        try lock.withLock {
            _finishes.append(Finish(id: id, reason: reason))
            if failFinish { throw StoreError.ioFailure }
            guard var session = stored[id] else { throw StoreError.notFound }
            session.endedAt = date
            session.endReason = reason
            session.sampleCount = _appended.reduce(0) { $0 + $1.count }
            stored[id] = session
            return session
        }
    }

    func finishUnfinishedSessions(at date: Date) async throws -> [DriveSession] {
        try lock.withLock {
            _unfinishedCalls += 1
            if failFinishUnfinished { throw StoreError.ioFailure }
            return unfinishedResult
        }
    }

    func sessions(for vehicleID: VehicleID?) async throws -> [DriveSession] { lock.withLock { Array(stored.values) } }
    func session(_ id: SessionID) async throws -> DriveSession? { lock.withLock { stored[id] } }
    func pids(for id: SessionID) async throws -> [SessionPID] { lock.withLock { _begun.first { $0.session.id == id }?.pids ?? [] } }
    func samples(for id: SessionID, afterSequence: Int64, limit: Int) async throws -> [SessionSample] {
        Array(allSamples.filter { $0.sequence > afterSequence }.prefix(limit))
    }
    func delete(_ id: SessionID) async throws { lock.withLock { stored[id] = nil } }
    func evictSamples(for id: SessionID) async throws {}
    func importArchive(_ archive: SessionArchive) async throws {}
}
