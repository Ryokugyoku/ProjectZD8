import XCTest
@testable import ProjectZD8

/// `GRDBVehiclePIDSettingRepository` の契約を検証します。
final class GRDBVehiclePIDSettingRepositoryTests: XCTestCase {
    private typealias Fixtures = PersistenceTestFixtures

    private func makeFixture() async throws -> (GRDBVehiclePIDSettingRepository, VehicleID) {
        let database = try AppDatabaseTesting.makeDatabase()
        let vehicle = Fixtures.vehicle()
        try await GRDBVehicleRepository(database: database, photoFiles: Fixtures.temporaryPhotoStore(self)).save(vehicle)
        return (GRDBVehiclePIDSettingRepository(database: database), vehicle.id)
    }

    /// 責務: 未登録PIDが対応・収集有効で追加されることを確認します。
    func testMergeAddsNewSupportedPIDsEnabled() async throws {
        let (repository, vehicleID) = try await makeFixture()
        try await repository.mergeDiscovered([Fixtures.request(12), Fixtures.request(13)], for: vehicleID, at: Fixtures.date(5))
        let settings = try await repository.settings(for: vehicleID)
        XCTAssertEqual(settings.map(\.request.pid), [12, 13])
        XCTAssertTrue(settings.allSatisfy { $0.isSupported && $0.isCollectionEnabled && $0.discoveredAt == Fixtures.date(5) })
    }

    /// 責務: 再探索で既存の収集設定が保たれ、結果から外れたPIDが非対応になることを確認します。
    func testMergePreservesCollectionAndMarksMissingUnsupported() async throws {
        let (repository, vehicleID) = try await makeFixture()
        try await repository.mergeDiscovered([Fixtures.request(12), Fixtures.request(13)], for: vehicleID, at: Fixtures.date(5))
        try await repository.setCollectionEnabled(false, for: Fixtures.request(12), vehicleID: vehicleID)
        try await repository.mergeDiscovered([Fixtures.request(12), Fixtures.request(14)], for: vehicleID, at: Fixtures.date(9))
        let byPID = Dictionary(uniqueKeysWithValues: try await repository.settings(for: vehicleID).map { ($0.request.pid, $0) })
        XCTAssertEqual(byPID[12]?.isCollectionEnabled, false)
        XCTAssertEqual(byPID[12]?.isSupported, true)
        XCTAssertEqual(byPID[13]?.isSupported, false)
        XCTAssertEqual(byPID[14]?.isCollectionEnabled, true)
        XCTAssertEqual(byPID[12]?.discoveredAt, Fixtures.date(9))
    }

    /// 責務: 存在しない設定の切り替えと存在しない車両への反映が `notFound` になることを確認します。
    func testMissingTargetsThrowNotFound() async throws {
        let (repository, vehicleID) = try await makeFixture()
        do {
            try await repository.setCollectionEnabled(true, for: Fixtures.request(1), vehicleID: vehicleID)
            XCTFail("notFound を期待")
        } catch {
            XCTAssertEqual(error as? StoreError, .notFound)
        }
        do {
            try await repository.mergeDiscovered([], for: VehicleID(), at: Fixtures.date())
            XCTFail("notFound を期待")
        } catch {
            XCTAssertEqual(error as? StoreError, .notFound)
        }
    }
}
