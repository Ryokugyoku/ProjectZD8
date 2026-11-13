import Foundation
@testable import ProjectZD8

/// 分析テスト用のメモリ上のセッション保管庫です。サンプルの読み出しページ数を数えます。
actor AnalysisFakeSessionRepository: SessionRepository {
    private var storedSessions: [SessionID: DriveSession] = [:]
    private var storedPIDs: [SessionID: [SessionPID]] = [:]
    private var storedSamples: [SessionID: [SessionSample]] = [:]
    /// `samples` が呼ばれた回数です。
    private(set) var samplePageRequests = 0

    /// 責務: 空の保管庫を生成します。
    init() {}

    /// 責務: テスト用にセッション一式を登録します。
    func seed(_ session: DriveSession, pids: [SessionPID], samples: [SessionSample]) {
        storedSessions[session.id] = session
        storedPIDs[session.id] = pids
        storedSamples[session.id] = samples
    }

    /// 責務: クラウド復元を模して、セッションをローカルへ戻します。
    func markLocal(_ id: SessionID) {
        storedSessions[id]?.rawAvailability = .local
    }

    func begin(_ session: DriveSession, pids: [SessionPID]) async throws { throw StoreError.invalidState }
    func append(_ samples: [SessionSample], to id: SessionID) async throws { throw StoreError.invalidState }
    func recordDistance(startKilometers: Double, endKilometers: Double, source: DistanceSource, for id: SessionID) async throws { throw StoreError.invalidState }
    func finish(_ id: SessionID, at date: Date, reason: SessionEndReason) async throws -> DriveSession { throw StoreError.invalidState }
    func finishUnfinishedSessions(at date: Date) async throws -> [DriveSession] { throw StoreError.invalidState }
    func delete(_ id: SessionID) async throws { throw StoreError.invalidState }
    func evictSamples(for id: SessionID) async throws { throw StoreError.invalidState }
    func importArchive(_ archive: SessionArchive) async throws { throw StoreError.invalidState }

    func sessions(for vehicleID: VehicleID?) async throws -> [DriveSession] {
        storedSessions.values.filter { vehicleID == nil || $0.vehicleID == vehicleID }.sorted { $0.startedAt > $1.startedAt }
    }

    func session(_ id: SessionID) async throws -> DriveSession? { storedSessions[id] }

    func pids(for id: SessionID) async throws -> [SessionPID] { storedPIDs[id] ?? [] }

    func samples(for id: SessionID, afterSequence: Int64, limit: Int) async throws -> [SessionSample] {
        samplePageRequests += 1
        return Array((storedSamples[id] ?? []).filter { $0.sequence > afterSequence }.prefix(limit))
    }
}
