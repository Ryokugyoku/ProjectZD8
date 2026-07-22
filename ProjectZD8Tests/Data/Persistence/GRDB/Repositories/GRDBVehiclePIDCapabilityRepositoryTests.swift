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
