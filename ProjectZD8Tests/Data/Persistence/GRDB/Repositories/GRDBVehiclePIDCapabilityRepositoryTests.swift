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
