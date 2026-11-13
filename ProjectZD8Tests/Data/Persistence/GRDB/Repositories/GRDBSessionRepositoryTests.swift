import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBSessionRepository` の契約・追記専用・削除規則を検証します。
final class GRDBSessionRepositoryTests: XCTestCase {
    private typealias Fixtures = PersistenceTestFixtures

    private struct Context {
        let database: AppDatabase
        let repository: GRDBSessionRepository
        let clock: PersistenceTestClock
        let vehicleID: VehicleID
    }

    private func makeContext() async throws -> Context {
        let database = try AppDatabaseTesting.makeDatabase()
        let clock = PersistenceTestClock(Fixtures.date(1000))
        let vehicle = Fixtures.vehicle()
        try await GRDBVehicleRepository(database: database, photoFiles: Fixtures.temporaryPhotoStore(self)).save(vehicle)
        return Context(database: database, repository: GRDBSessionRepository(database: database, now: { clock.now }), clock: clock, vehicleID: vehicle.id)
    }

    private func begin(_ context: Context, startedAt: TimeInterval = 10) async throws -> DriveSession {
        let session = Fixtures.session(vehicleID: context.vehicleID, startedAt: Fixtures.date(startedAt))
        try await context.repository.begin(session, pids: [Fixtures.sessionPID(ordinal: 0, pid: 12), Fixtures.sessionPID(ordinal: 1, pid: 13)])
        return session
    }

    private func expect(_ expected: StoreError, _ block: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await block()
            XCTFail("\(expected) を期待", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? StoreError, expected, file: file, line: line)
        }
    }

    /// 責務: 開始したセッションと取得条件が往復することを確認します。
    func testBeginPersistsSessionAndPIDsInOrder() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        let loaded = try await context.repository.session(session.id)
        XCTAssertEqual(loaded, session)
        let pids = try await context.repository.pids(for: session.id)
        XCTAssertEqual(pids.map(\.ordinal), [0, 1])
        XCTAssertEqual(pids[0], Fixtures.sessionPID(ordinal: 0, pid: 12))
    }

    /// 責務: 同一ID再開始が `invalidState`、車両不在が `notFound` になることを確認します。
    func testBeginPreconditions() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        await expect(.invalidState) { try await context.repository.begin(session, pids: []) }
        await expect(.notFound) { try await context.repository.begin(Fixtures.session(vehicleID: VehicleID()), pids: []) }
    }

    /// 責務: 追記が件数・応答数・ペイロード量を加算し、`modifiedAt` を変えないことを確認します。
    func testAppendUpdatesCountersButNotModifiedAt() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        try await context.repository.append([
            Fixtures.sample(0, payload: [1, 2, 3]), Fixtures.sample(1, outcome: .timedOut, payload: []), Fixtures.sample(2, payload: [9])
        ], to: session.id)
        try await context.repository.append([Fixtures.sample(3, outcome: .noData, payload: [])], to: session.id)
        let loaded = try Fixtures.unwrapped(try await context.repository.session(session.id))
        XCTAssertEqual(loaded.sampleCount, 4)
        XCTAssertEqual(loaded.respondedCount, 2)
        XCTAssertEqual(loaded.payloadByteCount, 4)
        XCTAssertEqual(loaded.modifiedAt, session.modifiedAt)
    }

    /// 責務: サンプルがページングして通し番号順に読めることを確認します。
    func testSamplesPaginateBySequence() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        try await context.repository.append((0..<5).map { Fixtures.sample(Int64($0)) }, to: session.id)
        let first = try await context.repository.samples(for: session.id, afterSequence: -1, limit: 2)
        XCTAssertEqual(first.map(\.sequence), [0, 1])
        let rest = try await context.repository.samples(for: session.id, afterSequence: 1, limit: 10)
        XCTAssertEqual(rest.map(\.sequence), [2, 3, 4])
        XCTAssertEqual(first[0], Fixtures.sample(0))
    }

    /// 責務: 追記が原子的で、重複通し番号の失敗が何も残さないことを確認します。
    func testAppendIsAtomic() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        try await context.repository.append([Fixtures.sample(0)], to: session.id)
        await expect(.ioFailure) { try await context.repository.append([Fixtures.sample(1), Fixtures.sample(0)], to: session.id) }
        XCTAssertEqual(try Fixtures.count(context.database, "session_samples"), 1)
        let loaded = try Fixtures.unwrapped(try await context.repository.session(session.id))
        XCTAssertEqual(loaded.sampleCount, 1)
    }

    /// 責務: 存在しない・終了済みのセッションへの追記が拒否されることを確認します。
    func testAppendPreconditions() async throws {
        let context = try await makeContext()
        await expect(.notFound) { try await context.repository.append([Fixtures.sample(0)], to: SessionID()) }
        let session = try await begin(context)
        _ = try await context.repository.finish(session.id, at: Fixtures.date(20), reason: .userStopped)
        await expect(.invalidState) { try await context.repository.append([Fixtures.sample(0)], to: session.id) }
    }

    /// 責務: 保存済みサンプルとPIDを更新できないことを確認します(追記専用)。
    func testRawRowsAreAppendOnly() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        try await context.repository.append([Fixtures.sample(0)], to: session.id)
        XCTAssertThrowsError(try Fixtures.execute(context.database, "UPDATE session_samples SET payload = x'00'"))
        XCTAssertThrowsError(try Fixtures.execute(context.database, "UPDATE session_pids SET unit = 'x'"))
    }

    /// 責務: 距離記録が `modifiedAt` を更新することを確認します。
    func testRecordDistanceUpdatesModifiedAt() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        try await context.repository.recordDistance(startKilometers: 100, endKilometers: 112.5, source: .odometer, for: session.id)
        let loaded = try Fixtures.unwrapped(try await context.repository.session(session.id))
        XCTAssertEqual(loaded.recordedDistanceKilometers, 12.5)
        XCTAssertEqual(loaded.distanceSource, .odometer)
        XCTAssertEqual(loaded.modifiedAt, Fixtures.date(1000))
        await expect(.notFound) { try await context.repository.recordDistance(startKilometers: 0, endKilometers: 1, source: .odometer, for: SessionID()) }
    }

    /// 責務: 終了が終了日時・理由・`modifiedAt` を設定し、二重終了が `invalidState` になることを確認します。
    func testFinishSetsEndAndRejectsSecondFinish() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        let finished = try await context.repository.finish(session.id, at: Fixtures.date(60), reason: .connectionLost)
        XCTAssertEqual(finished.endedAt, Fixtures.date(60))
        XCTAssertEqual(finished.endReason, .connectionLost)
        XCTAssertEqual(finished.modifiedAt, Fixtures.date(1000))
        XCTAssertFalse(finished.isRecording)
        await expect(.invalidState) { _ = try await context.repository.finish(session.id, at: Fixtures.date(70), reason: .userStopped) }
        await expect(.notFound) { _ = try await context.repository.finish(SessionID(), at: Fixtures.date(70), reason: .userStopped) }
    }

    /// 責務: 未終了セッションだけが `appTerminated` で終了することを確認します。
    func testFinishUnfinishedSessions() async throws {
        let context = try await makeContext()
        let open = try await begin(context, startedAt: 10)
        let closed = try await begin(context, startedAt: 20)
        _ = try await context.repository.finish(closed.id, at: Fixtures.date(30), reason: .userStopped)
        let finished = try await context.repository.finishUnfinishedSessions(at: Fixtures.date(500))
        XCTAssertEqual(finished.map(\.id), [open.id])
        XCTAssertEqual(finished.first?.endReason, .appTerminated)
        XCTAssertEqual(finished.first?.endedAt, Fixtures.date(500))
        let again = try await context.repository.finishUnfinishedSessions(at: Fixtures.date(600))
        XCTAssertTrue(again.isEmpty)
    }

    /// 責務: 一覧が開始日時の新しい順で、車両で絞り込めることを確認します。
    func testSessionsOrderingAndFiltering() async throws {
        let context = try await makeContext()
        let older = try await begin(context, startedAt: 10)
        let newer = try await begin(context, startedAt: 90)
        let other = Fixtures.vehicle(name: "other")
        try await GRDBVehicleRepository(database: context.database, photoFiles: Fixtures.temporaryPhotoStore(self)).save(other)
        try await context.repository.begin(Fixtures.session(vehicleID: other.id), pids: [])
        let all = try await context.repository.sessions(for: nil)
        XCTAssertEqual(all.count, 3)
        let mine = try await context.repository.sessions(for: context.vehicleID).map(\.id)
        XCTAssertEqual(mine, [newer.id, older.id])
    }

    /// 責務: 未同期セッションの削除が行・PID・サンプルを物理削除することを確認します。
    func testDeleteUnsyncedIsPhysical() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        try await context.repository.append([Fixtures.sample(0)], to: session.id)
        try await context.repository.delete(session.id)
        for table in ["sessions", "session_pids", "session_samples"] { XCTAssertEqual(try Fixtures.count(context.database, table), 0, table) }
        await expect(.notFound) { try await context.repository.delete(session.id) }
    }

    /// 責務: 同期済みセッションの削除が行を墓標化しつつPID・サンプルを即時削除することを確認します。
    func testDeleteSyncedTombstonesRowButDropsRawImmediately() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        try await context.repository.append([Fixtures.sample(0)], to: session.id)
        try Fixtures.markSynced(context.database, recordType: "RTDriveSession", id: session.id.rowID)
        try await context.repository.delete(session.id)
        XCTAssertEqual(try Fixtures.count(context.database, "session_samples"), 0)
        XCTAssertEqual(try Fixtures.count(context.database, "session_pids"), 0)
        let expected = Fixtures.date(1000).epochMilliseconds
        XCTAssertEqual(try Fixtures.count(context.database, "sessions", where: "deletedAt = \(expected) AND modifiedAt = \(expected)"), 1)
        let loaded = try await context.repository.session(session.id)
        XCTAssertNil(loaded)
        let listed = try await context.repository.sessions(for: nil)
        XCTAssertTrue(listed.isEmpty)
    }

    /// 責務: 解放の前提条件(終了済み・アーカイブ保存済み)を検証します。
    func testEvictRequiresEndedAndArchived() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        try await context.repository.append([Fixtures.sample(0)], to: session.id)
        await expect(.invalidState) { try await context.repository.evictSamples(for: session.id) }
        _ = try await context.repository.finish(session.id, at: Fixtures.date(20), reason: .userStopped)
        await expect(.invalidState) { try await context.repository.evictSamples(for: session.id) }
        await expect(.notFound) { try await context.repository.evictSamples(for: SessionID()) }
        XCTAssertEqual(try Fixtures.count(context.database, "session_samples"), 1)
    }

    /// 責務: 解放がサンプルだけを消し、`cloudOnly` にして `modifiedAt` を変えないことを確認します。
    func testEvictRemovesSamplesAndKeepsModifiedAt() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        try await context.repository.append([Fixtures.sample(0), Fixtures.sample(1)], to: session.id)
        let finished = try await context.repository.finish(session.id, at: Fixtures.date(20), reason: .userStopped)
        try Fixtures.execute(context.database, "UPDATE sessions SET archiveDigest = 'abc'")
        context.clock.advance(by: 100)
        try await context.repository.evictSamples(for: session.id)
        let loaded = try Fixtures.unwrapped(try await context.repository.session(session.id))
        XCTAssertEqual(loaded.rawAvailability, .cloudOnly)
        XCTAssertEqual(loaded.modifiedAt, finished.modifiedAt)
        XCTAssertEqual(loaded.sampleCount, 2)
        XCTAssertEqual(try Fixtures.count(context.database, "session_samples"), 0)
        XCTAssertEqual(try Fixtures.count(context.database, "session_pids"), 2)
    }

    /// 責務: アーカイブの取り込みが解放済みセッションを置換・復元し、件数を整合させることを確認します。
    func testImportArchiveRestoresEvictedSession() async throws {
        let context = try await makeContext()
        let session = try await begin(context)
        try await context.repository.append([Fixtures.sample(0)], to: session.id)
        var ended = try await context.repository.finish(session.id, at: Fixtures.date(20), reason: .userStopped)
        try Fixtures.execute(context.database, "UPDATE sessions SET archiveDigest = 'abc'")
        try await context.repository.evictSamples(for: session.id)

        ended.archiveDigest = "abc"
        ended.sampleCount = 999
        ended.rawAvailability = .cloudOnly
        let samples = [Fixtures.sample(0, payload: [1, 2, 3]), Fixtures.sample(1, outcome: .noData, payload: []), Fixtures.sample(2, payload: [7])]
        let pids = [Fixtures.sessionPID(ordinal: 0, pid: 12)]
        try await context.repository.importArchive(SessionArchive(session: ended, pids: pids, samples: samples))

        let loaded = try Fixtures.unwrapped(try await context.repository.session(session.id))
        XCTAssertEqual(loaded.rawAvailability, .local)
        XCTAssertEqual(loaded.sampleCount, 3)
        XCTAssertEqual(loaded.respondedCount, 2)
        XCTAssertEqual(loaded.payloadByteCount, 4)
        XCTAssertEqual(loaded.archiveDigest, "abc")
        let restored = try await context.repository.samples(for: session.id, afterSequence: -1, limit: 10)
        XCTAssertEqual(restored, samples)
        let restoredPIDs = try await context.repository.pids(for: session.id)
        XCTAssertEqual(restoredPIDs, pids)
    }

    /// 責務: 未登録のセッションを取り込めること、車両不在が `notFound` になることを確認します。
    func testImportArchiveInsertsNewSession() async throws {
        let context = try await makeContext()
        var session = Fixtures.session(vehicleID: context.vehicleID)
        session.endedAt = Fixtures.date(50)
        session.endReason = .userStopped
        try await context.repository.importArchive(SessionArchive(session: session, pids: [], samples: [Fixtures.sample(0)]))
        let loaded = try await context.repository.session(session.id)
        XCTAssertEqual(loaded?.sampleCount, 1)
        let orphan = Fixtures.session(vehicleID: VehicleID())
        await expect(.notFound) { try await context.repository.importArchive(SessionArchive(session: orphan, pids: [], samples: [])) }
    }
}
