import XCTest
@testable import ProjectZD8

/// `GRDBStoreChangeObserver` が領域ごとの書き込みを通知することを検証します。
final class GRDBStoreChangeObserverTests: XCTestCase {
    /// 書き込み開始を示すスレッドセーフなフラグです。
    private final class WriteFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set() {
            lock.lock()
            value = true
            lock.unlock()
        }
    }

    private typealias Fixtures = PersistenceTestFixtures

    /// 責務: ストリームから1要素を待ちます。`timeout` 内に来なければ `nil` を返します。
    private func nextElement(of stream: AsyncStream<Void>, timeout: Duration = .seconds(2)) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// 責務: 購読開始時には流れず、書き込み開始後にだけ流れることを確認します。
    func testEmitsOnlyOnLaterChanges() async throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let vehicles = GRDBVehicleRepository(database: database, photoFiles: Fixtures.temporaryPhotoStore(self))
        try await vehicles.save(Fixtures.vehicle(name: "before"))
        let stream = GRDBStoreChangeObserver(database: database).changes(in: [.vehicles])
        let writeStarted = WriteFlag()
        let waiter = Task { () -> Bool? in
            var iterator = stream.makeAsyncIterator()
            guard await iterator.next() != nil else { return nil }
            return writeStarted.isSet
        }
        try await Task.sleep(for: .milliseconds(400))
        writeStarted.set()
        try await vehicles.save(Fixtures.vehicle(name: "after"))
        let result = await withTaskGroup(of: Bool?.self) { group in
            group.addTask { await waiter.value }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        XCTAssertEqual(result, true)
    }

    /// 責務: 購読していない領域の書き込みでは流れないことを確認します。
    func testIgnoresOtherAreas() async throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let vehicles = GRDBVehicleRepository(database: database, photoFiles: Fixtures.temporaryPhotoStore(self))
        let stream = GRDBStoreChangeObserver(database: database).changes(in: [.maintenance])
        let waiter = Task { await nextElement(of: stream, timeout: .milliseconds(500)) }
        try await Task.sleep(for: .milliseconds(100))
        try await vehicles.save(Fixtures.vehicle())
        let emitted = await waiter.value
        XCTAssertFalse(emitted)
    }

    /// 責務: セッションのサンプル追記が `sessions` 領域の変更として通知されることを確認します。
    func testSessionAppendNotifiesSessionsArea() async throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let vehicle = Fixtures.vehicle()
        try await GRDBVehicleRepository(database: database, photoFiles: Fixtures.temporaryPhotoStore(self)).save(vehicle)
        let sessions = GRDBSessionRepository(database: database)
        let session = Fixtures.session(vehicleID: vehicle.id)
        try await sessions.begin(session, pids: [])
        let stream = GRDBStoreChangeObserver(database: database).changes(in: [.sessions])
        let waiter = Task { await nextElement(of: stream) }
        try await Task.sleep(for: .milliseconds(100))
        try await sessions.append([Fixtures.sample(0)], to: session.id)
        let emitted = await waiter.value
        XCTAssertTrue(emitted)
    }
}
