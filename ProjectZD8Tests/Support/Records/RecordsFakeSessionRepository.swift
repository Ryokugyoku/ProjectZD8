import Foundation
import Synchronization
@testable import ProjectZD8

/// メモリ上のテスト用 `SessionRepository` です。一覧・取得・削除・領域解放だけを実装します。
final class RecordsFakeSessionRepository: SessionRepository, Sendable {
    private let state: Mutex<State>

    private struct State {
        var sessions: [DriveSession]
        var deleted: [SessionID] = []
        var evicted: [SessionID] = []
        var listError: StoreError?
        var deleteError: StoreError?
        var evictError: StoreError?
        var failingEvictions: Set<SessionID> = []
    }

    init(sessions: [DriveSession] = []) {
        state = Mutex(State(sessions: sessions))
    }

    var stored: [DriveSession] { state.withLock { $0.sessions } }
    var deletedIDs: [SessionID] { state.withLock { $0.deleted } }
    var evictedIDs: [SessionID] { state.withLock { $0.evicted } }
    func setListError(_ error: StoreError?) { state.withLock { $0.listError = error } }
    func setDeleteError(_ error: StoreError?) { state.withLock { $0.deleteError = error } }
    func setEvictError(_ error: StoreError?) { state.withLock { $0.evictError = error } }
    func failEviction(of id: SessionID) { state.withLock { _ = $0.failingEvictions.insert(id) } }
    func replace(_ sessions: [DriveSession]) { state.withLock { $0.sessions = sessions } }

    func begin(_ session: DriveSession, pids: [SessionPID]) async throws { throw StoreError.invalidState }
    func append(_ samples: [SessionSample], to id: SessionID) async throws { throw StoreError.invalidState }
    func recordDistance(startKilometers: Double, endKilometers: Double, source: DistanceSource, for id: SessionID) async throws { throw StoreError.invalidState }
    func finish(_ id: SessionID, at date: Date, reason: SessionEndReason) async throws -> DriveSession { throw StoreError.invalidState }
    func finishUnfinishedSessions(at date: Date) async throws -> [DriveSession] { throw StoreError.invalidState }
    func pids(for id: SessionID) async throws -> [SessionPID] { throw StoreError.invalidState }
    func samples(for id: SessionID, afterSequence: Int64, limit: Int) async throws -> [SessionSample] { throw StoreError.invalidState }
    func importArchive(_ archive: SessionArchive) async throws { throw StoreError.invalidState }

    func sessions(for vehicleID: VehicleID?) async throws -> [DriveSession] {
        try state.withLock { s in
            if let error = s.listError { throw error }
            return s.sessions
                .filter { vehicleID == nil || $0.vehicleID == vehicleID }
                .sorted { $0.startedAt > $1.startedAt }
        }
    }

    func session(_ id: SessionID) async throws -> DriveSession? {
        try state.withLock { s in
            if let error = s.listError { throw error }
            return s.sessions.first { $0.id == id }
        }
    }

    func delete(_ id: SessionID) async throws {
        try state.withLock { s in
            if let error = s.deleteError { throw error }
            s.sessions.removeAll { $0.id == id }
            s.deleted.append(id)
        }
    }

    func evictSamples(for id: SessionID) async throws {
        try state.withLock { s in
            if let error = s.evictError { throw error }
            if s.failingEvictions.contains(id) { throw StoreError.ioFailure }
            guard let index = s.sessions.firstIndex(where: { $0.id == id }), s.sessions[index].archiveDigest != nil else {
                throw StoreError.invalidState
            }
            s.sessions[index].rawAvailability = .cloudOnly
            s.evicted.append(id)
        }
    }
}
