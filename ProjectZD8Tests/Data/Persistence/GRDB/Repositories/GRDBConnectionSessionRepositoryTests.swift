import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// GRDB接続セッション保存先の往復変換とアカウント分離を検証します。
@MainActor
final class GRDBConnectionSessionRepositoryTests: XCTestCase {
    /// 製品DBでPID定義Migrationと接続履歴Migrationを同時に利用できます。
    ///
    /// 責務: 接続履歴を先に移行してもPID定義スキーマを同じDBへ追加できることを確認します。
    func testSharedProductDatabaseAcceptsBothMigrators() throws {
        let queue = try DatabaseQueue()

        _ = try GRDBConnectionSessionRepository(databaseQueue: queue)
        _ = try GRDBOBDPIDDefinitionRepository(databaseQueue: queue)
    }

    /// 車両と終了原因を含むセッションを安定IDのまま保存して復元します。
    ///
    /// 責務: 1件の完了済み接続セッションがGRDB境界を欠落なく往復することを確認します。
    func testSaveAndLoadRoundTripPreservesVehicleAndEndReason() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let vehicle = VehicleProfile(vin: "TESTVIN", name: "ZD8")
        var session = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 100),
            vehicle: ConnectionSessionVehicle(profile: vehicle)
        )
        session.endedAt = Date(timeIntervalSince1970: 200)
        session.endReason = .userDisconnected
        session.startingOdometerKilometers = 98_765.4
        session.endingOdometerKilometers = 98_767.9

        try repository.save(session)
        let loaded = try XCTUnwrap(repository.sessions(for: "account").first)

        XCTAssertEqual(loaded, session)
        XCTAssertEqual(loaded.status, .completed)
        XCTAssertEqual(try XCTUnwrap(loaded.recordedDistanceKilometers), 2.5, accuracy: 0.000_1)
        XCTAssertTrue(try repository.sessions(for: "different-account").isEmpty)
    }
}
