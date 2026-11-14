import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// GRDB車両別対応PIDの初期登録と選択更新を検証します。
@MainActor
final class GRDBVehiclePIDCapabilityRepositoryTests: XCTestCase {
    /// 初回登録を車両IDで分離し、1件の選択だけを更新します。
    ///
    /// 責務: 複合主キーと車両単位照会および選択更新が同時に成立することを確認します。
    func testPersistsPerVehicleAndUpdatesOnlyRequestedPID() throws {
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: DatabaseQueue())
        let first = capability(pid: 0x0C)
        let second = capability(pid: 0x0D)
        try repository.insertInitial([first, second], for: vehicleID)

        try repository.setCollectionEnabled(false, for: second.id.request, vehicleID: vehicleID)

        let loaded = try repository.capabilities(for: vehicleID)
        XCTAssertEqual(loaded.map(\.id.request.pid), [0x0C, 0x0D])
        XCTAssertEqual(loaded.map(\.isCollectionEnabled), [true, false])
        XCTAssertEqual(try repository.capabilities(for: otherVehicleID), [])
    }

    /// 既存車両スコープへの再初期登録を拒否します。
    ///
    /// 責務: 収集選択を初回探索で上書きできないことを確認します。
    func testRejectsSecondInitialInsert() throws {
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: DatabaseQueue())
        try repository.insertInitial([capability(pid: 0x0C)], for: vehicleID)
        XCTAssertThrowsError(try repository.insertInitial([capability(pid: 0x0D)], for: vehicleID))
    }

    /// 拡張PID探索結果を既存の収集選択を壊さず追加します。
    ///
    /// 責務: 応答確認済みの車種専用PIDだけを追加し既存PIDの無効選択を保持することを確認します。
    func testMergeDiscoveredPreservesExistingSelectionAndAddsVehicleSpecificPID() throws {
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: DatabaseQueue())
        let standard = capability(pid: 0x0D)
        try repository.insertInitial([standard], for: vehicleID)
        try repository.setCollectionEnabled(false, for: standard.id.request, vehicleID: vehicleID)
        let discovered = VehiclePIDCapability(
            vehicleID: vehicleID,
            request: OBDPIDRequest(service: 0x21, pid: 0x17),
            isCollectionEnabled: true,
            discoveredAt: Date(timeIntervalSince1970: 200)
        )

        try repository.mergeDiscovered([standard, discovered], for: vehicleID)

        let loaded = try repository.capabilities(for: vehicleID)
        XCTAssertEqual(loaded.map(\.id.request), [standard.id.request, discovered.id.request])
        XCTAssertEqual(loaded.map(\.isCollectionEnabled), [false, true])
    }

    /// アカウント削除対象の車両別PID設定だけを一括削除します。
    ///
    /// 責務: 登録車両ID群の収集設定を削除し、別車両の設定を保持することを確認します。
    func testDeleteCapabilitiesRemovesOnlyRequestedVehicles() throws {
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: DatabaseQueue())
        try repository.insertInitial([capability(pid: 0x0C)], for: vehicleID)
        let retained = VehiclePIDCapability(
            vehicleID: otherVehicleID,
            request: OBDPIDRequest(service: 0x01, pid: 0x0D),
            isCollectionEnabled: true,
            discoveredAt: Date(timeIntervalSince1970: 100)
        )
        try repository.insertInitial([retained], for: otherVehicleID)

        try repository.deleteCapabilities(for: [vehicleID])

        XCTAssertTrue(try repository.capabilities(for: vehicleID).isEmpty)
        XCTAssertEqual(try repository.capabilities(for: otherVehicleID), [retained])
    }

    /// UUIDでない車両ID列の保存行は照会対象外であり、有効行の読込を妨げません。
    ///
    /// 責務: 破損した別行が混在しても、指定車両の有効行だけが復元されることを確認します。
    func testCapabilitiesIgnoresRowsOfOtherVehicleIdentifiers() throws {
        let queue = try DatabaseQueue()
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: queue)
        try insertRaw(queue, vehicleID: "not-a-uuid", service: 1, pid: 12)
        try insertRaw(queue, vehicleID: vehicleID.rawValue.uuidString.lowercased(), service: 1, pid: 13)

        XCTAssertEqual(try repository.capabilities(for: vehicleID).map(\.id.request.pid), [13])
    }

    /// Service範囲外の保存行を明示的な失敗にします。
    ///
    /// 責務: 車両IDが有効でもServiceがUInt8範囲外なら復元せずエラーにすることを確認します。
    func testCapabilitiesThrowsForOutOfRangeService() throws {
        let queue = try DatabaseQueue()
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: queue)
        try insertRaw(queue, vehicleID: vehicleID.rawValue.uuidString.lowercased(), service: 300, pid: 12)

        XCTAssertThrowsError(try repository.capabilities(for: vehicleID)) { error in
            XCTAssertTrue(error is DatabaseError)
        }
    }

    /// PID範囲外の保存行も明示的な失敗にします。
    ///
    /// 責務: 車両IDが有効でもPIDがUInt8範囲外なら復元せずエラーにすることを確認します。
    func testCapabilitiesThrowsForOutOfRangePID() throws {
        let queue = try DatabaseQueue()
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: queue)
        try insertRaw(queue, vehicleID: vehicleID.rawValue.uuidString.lowercased(), service: 1, pid: 256)

        XCTAssertThrowsError(try repository.capabilities(for: vehicleID)) { error in
            XCTAssertTrue(error is DatabaseError)
        }
    }

    /// 車両IDが一致しない初期登録を拒否し、何も保存しません。
    ///
    /// 責務: 別車両の設定が混ざった初期登録が失敗し、先行して有効だった行も巻き戻ることを確認します。
    func testInsertInitialRejectsMismatchedVehicleAndRollsBack() throws {
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: DatabaseQueue())
        let valid = capability(pid: 0x0C)
        let foreign = VehiclePIDCapability(
            vehicleID: otherVehicleID, request: .init(service: 0x01, pid: 0x0D),
            isCollectionEnabled: true, discoveredAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertThrowsError(try repository.insertInitial([valid, foreign], for: vehicleID))

        XCTAssertEqual(try repository.capabilities(for: vehicleID), [])
        XCTAssertEqual(try repository.capabilities(for: otherVehicleID), [])
    }

    /// 収集無効の設定を含む初期登録を拒否します。
    ///
    /// 責務: 初回探索結果は全件収集有効である契約を、無効設定の混入で破れないことを確認します。
    func testInsertInitialRejectsDisabledCapability() throws {
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: DatabaseQueue())
        let disabled = VehiclePIDCapability(
            vehicleID: vehicleID, request: .init(service: 0x01, pid: 0x0C),
            isCollectionEnabled: false, discoveredAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertThrowsError(try repository.insertInitial([disabled], for: vehicleID))

        XCTAssertEqual(try repository.capabilities(for: vehicleID), [])
    }

    /// 車両不一致の探索結果を拒否し、既存選択を変更しません。
    ///
    /// 責務: mergeDiscoveredが別車両のPIDで失敗し、先に有効だった追加分も保存されないことを確認します。
    func testMergeDiscoveredRejectsMismatchedVehicle() throws {
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: DatabaseQueue())
        let existing = capability(pid: 0x0C)
        try repository.insertInitial([existing], for: vehicleID)
        let valid = capability(pid: 0x0D)
        let foreign = VehiclePIDCapability(
            vehicleID: otherVehicleID, request: .init(service: 0x01, pid: 0x0E),
            isCollectionEnabled: true, discoveredAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertThrowsError(try repository.mergeDiscovered([valid, foreign], for: vehicleID))

        XCTAssertEqual(try repository.capabilities(for: vehicleID), [existing])
        XCTAssertEqual(try repository.capabilities(for: otherVehicleID), [])
    }

    /// 収集無効の探索結果を拒否します。
    ///
    /// 責務: mergeDiscoveredが無効設定の追加を許さず、保存内容を変えないことを確認します。
    func testMergeDiscoveredRejectsDisabledCapability() throws {
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: DatabaseQueue())
        let disabled = VehiclePIDCapability(
            vehicleID: vehicleID, request: .init(service: 0x01, pid: 0x0C),
            isCollectionEnabled: false, discoveredAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertThrowsError(try repository.mergeDiscovered([disabled], for: vehicleID))

        XCTAssertEqual(try repository.capabilities(for: vehicleID), [])
    }

    /// 存在しないPIDの選択更新を失敗させます。
    ///
    /// 責務: 対象不在のsetCollectionEnabledが成功扱いにならず、既存行も変わらないことを確認します。
    func testSetCollectionEnabledThrowsWhenTargetIsMissing() throws {
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: DatabaseQueue())
        let existing = capability(pid: 0x0C)
        try repository.insertInitial([existing], for: vehicleID)

        XCTAssertThrowsError(try repository.setCollectionEnabled(false, for: .init(service: 0x01, pid: 0x0D), vehicleID: vehicleID))

        XCTAssertEqual(try repository.capabilities(for: vehicleID), [existing])
    }

    /// 空の車両ID群の削除は何も削除しません。
    ///
    /// 責務: deleteCapabilitiesが空配列を早期に無操作として扱い、既存設定を保持することを確認します。
    func testDeleteCapabilitiesWithEmptyIDsKeepsRecords() throws {
        let repository = try GRDBVehiclePIDCapabilityRepository(databaseQueue: DatabaseQueue())
        let existing = capability(pid: 0x0C)
        try repository.insertInitial([existing], for: vehicleID)

        try repository.deleteCapabilities(for: [])

        XCTAssertEqual(try repository.capabilities(for: vehicleID), [existing])
    }

    /// 制約検証を無効化して保存行を直接挿入します。
    ///
    /// 責務: CHECK制約を迂回した不正な行を、復元失敗経路の入力として用意します。
    /// - Parameters:
    ///   - queue: 挿入先DB Queue。
    ///   - vehicleID: 車両ID列の文字列。
    ///   - service: Service列の値。
    ///   - pid: PID列の値。
    /// - Throws: SQLite書込みに失敗した場合のエラー。
    private func insertRaw(_ queue: DatabaseQueue, vehicleID: String, service: Int, pid: Int) throws {
        try queue.writeWithoutTransaction { database in
            try database.execute(sql: "PRAGMA ignore_check_constraints = 1")
            try database.execute(
                sql: "INSERT INTO vehicle_pid_capabilities (vehicleID, service, pid, isCollectionEnabled, discoveredAt) VALUES (?, ?, ?, 1, 0)",
                arguments: [vehicleID, service, pid]
            )
            try database.execute(sql: "PRAGMA ignore_check_constraints = 0")
        }
    }

    /// 指定PIDの固定対応設定を生成します。
    ///
    /// 責務: 1件のテスト用PIDを全件収集有効の車両設定へ変換します。
    /// - Parameter pid: Service 01 PID番号。
    /// - Returns: 固定車両へ属する対応PID設定。
    private func capability(pid: UInt8) -> VehiclePIDCapability {
        .init(vehicleID: vehicleID, request: .init(service: 0x01, pid: pid), isCollectionEnabled: true, discoveredAt: Date(timeIntervalSince1970: 100))
    }

    /// 主テスト車両IDです。
    private var vehicleID: VehicleID { .init(rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!) }
    /// 分離確認用車両IDです。
    private var otherVehicleID: VehicleID { .init(rawValue: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!) }
}
