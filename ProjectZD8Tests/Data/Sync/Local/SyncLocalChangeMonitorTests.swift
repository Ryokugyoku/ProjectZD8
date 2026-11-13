import GRDB
import Synchronization
import XCTest
@testable import ProjectZD8

/// ローカル書き込みの検知を確認します。
final class SyncLocalChangeMonitorTests: XCTestCase {
    /// 責務: 同期対象の行の書き込みは検知し、記録中のカウンター更新は検知しないことを確認します。
    func testDetectsSyncedColumnsButNotSampleCounters() async throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let vehicle = SyncTestFixtures.vehicle()
        let session = SyncTestFixtures.session(vehicleID: vehicle.id, ended: false)
        try await database.writer.write { db in
            try vehicle.insert(db)
            try session.insert(db)
        }
        let counter = SyncMonitorEventCounter()
        let changes = SyncLocalChangeMonitor(database: database).changes()
        let consumer = Task {
            for await _ in changes { counter.increment() }
        }
        defer { consumer.cancel() }

        try await database.writer.write { db in
            try db.execute(sql: "UPDATE sessions SET sampleCount = sampleCount + 1 WHERE id = ?", arguments: [session.id])
        }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(counter.value, 0)

        try await database.writer.write { db in
            try db.execute(sql: "UPDATE sessions SET endedAt = 300, endReason = 'userStopped', modifiedAt = 300 WHERE id = ?", arguments: [session.id])
        }
        try await Self.waitUntil { counter.value == 1 }

        try await database.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET name = 'x' WHERE id = ?", arguments: [vehicle.id])
        }
        try await Self.waitUntil { counter.value == 2 }
    }

    /// 責務: 条件が成り立つまで最大2秒待ちます。
    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}

/// 受け取った通知の数を数えます。
private final class SyncMonitorEventCounter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    func increment() {
        count.withLock { $0 += 1 }
    }
}
