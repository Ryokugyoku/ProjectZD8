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

    /// Rawログ追記後にライフサイクル保存しても集計と車両関連付けを保持します。
    ///
    /// 責務: 取得中のRaw応答と終了更新が同じセッションの永続状態として共存することを確認します。
    func testRawEntriesSurviveSessionFinalizationAndRemainVehicleScoped() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let vehicle = VehicleProfile(vin: "TESTVIN-ZD8", name: "BRZ")
        var session = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 100),
            vehicle: ConnectionSessionVehicle(profile: vehicle)
        )
        try repository.save(session)

        try repository.append(
            OBDRawResponseObservation(
                observedAt: Date(timeIntervalSince1970: 101),
                batchElapsedNanoseconds: 4_200_000,
                request: OBDPIDRequest(service: 0x01, pid: 0x0C),
                payload: [0x1A, 0xF8]
            ),
            to: session.id
        )
        try repository.append(
            OBDRawResponseObservation(
                observedAt: Date(timeIntervalSince1970: 102),
                batchElapsedNanoseconds: 5_100_000,
                request: OBDPIDRequest(service: 0x01, pid: 0x05),
                payload: [0x85]
            ),
            to: session.id
        )
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        try repository.save(session)

        let loaded = try XCTUnwrap(repository.sessions(for: "account").first)
        let entries = try repository.entries(for: session.id)

        XCTAssertEqual(loaded.vehicle?.displayIdentifier, "TESTVIN-ZD8")
        XCTAssertEqual(loaded.rawLogSummary.recordCount, 2)
        XCTAssertEqual(loaded.rawLogSummary.byteCount, 3)
        XCTAssertEqual(loaded.rawLogSummary.localState, .available)
        XCTAssertEqual(loaded.rawLogSummary.cloudState, .pending)
        XCTAssertEqual(entries.map(\.sequence), [0, 1])
        XCTAssertEqual(entries.map(\.payload), [[0x1A, 0xF8], [0x85]])
    }

    /// 一覧表示のRaw集計は壊れた概要列ではなく実際の子ログ行を使用します。
    ///
    /// 責務: ローカルRaw保有セッションの表示件数と容量を実ログから復元できることを確認します。
    func testSessionsUseActualRawRowsForLocalSummary() throws {
        let queue = try DatabaseQueue()
        let repository = try GRDBConnectionSessionRepository(databaseQueue: queue)
        let session = ConnectionSession(accountIdentifier: "account")
        try repository.save(session)
        try repository.append(
            OBDRawResponseObservation(
                observedAt: Date(),
                batchElapsedNanoseconds: 1,
                request: OBDPIDRequest(service: 0x01, pid: 0x0C),
                payload: [0x01, 0x02, 0x03]
            ),
            to: session.id
        )
        try queue.write { database in
            try database.execute(
                sql: "UPDATE connection_sessions SET rawRecordCount = 99, rawByteCount = 999, localRawState = 'empty' WHERE id = ?",
                arguments: [session.id.rawValue.uuidString.lowercased()]
            )
        }

        let loaded = try XCTUnwrap(repository.sessions(for: "account").first)

        XCTAssertEqual(loaded.rawLogSummary.recordCount, 1)
        XCTAssertEqual(loaded.rawLogSummary.byteCount, 3)
        XCTAssertEqual(loaded.rawLogSummary.localState, .available)
    }

    /// セッション単位削除は所有者を確認して子Rawログも物理削除します。
    ///
    /// 責務: 1件の所有者確認済みセッション削除が別アカウントを保持してCascade削除することを確認します。
    func testDeleteSessionRemovesOnlyOwnedSessionAndRawEntries() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let deleted = ConnectionSession(accountIdentifier: "account")
        let retained = ConnectionSession(accountIdentifier: "other")
        try repository.save(deleted)
        try repository.save(retained)
        try repository.append(
            OBDRawResponseObservation(
                observedAt: Date(),
                batchElapsedNanoseconds: 1,
                request: OBDPIDRequest(service: 0x01, pid: 0x0D),
                payload: [0x20]
            ),
            to: deleted.id
        )

        XCTAssertThrowsError(try repository.deleteSession(deleted.id, for: "other"))
        try repository.deleteSession(deleted.id, for: "account")

        XCTAssertTrue(try repository.sessions(for: "account").isEmpty)
        XCTAssertTrue(try repository.entries(for: deleted.id).isEmpty)
        XCTAssertEqual(try repository.sessions(for: "other").map(\.id), [retained.id])
    }

    /// Mac取込証跡と集計を残したまま現在端末のRaw Payloadだけを除去します。
    ///
    /// 責務: iPhoneローカル除去が履歴、車両、件数、およびMac受領証を破壊しないことを確認します。
    func testLocalRemovalKeepsSummaryAndMatchingMacReceipt() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        try repository.save(session)
        try repository.append(
            OBDRawResponseObservation(
                observedAt: Date(timeIntervalSince1970: 101),
                batchElapsedNanoseconds: 2_000_000,
                request: OBDPIDRequest(service: 0x01, pid: 0x0D),
                payload: [0x32]
            ),
            to: session.id
        )
        session.endedAt = Date(timeIntervalSince1970: 102)
        session.endReason = .userDisconnected
        try repository.save(session)
        try repository.markCloudUploaded(sessionID: session.id, manifestDigest: "digest")
        let receipt = ConnectionSessionMacImportReceipt(
            deviceID: "mac-installation",
            deviceName: "Garage Mac",
            importedAt: Date(timeIntervalSince1970: 103),
            manifestDigest: "digest"
        )
        try repository.markMacImported(receipt, sessionID: session.id)

        try repository.removeLocalEntries(for: session.id)

        let loaded = try XCTUnwrap(repository.sessions(for: "account").first)
        XCTAssertEqual(loaded.rawLogSummary.recordCount, 1)
        XCTAssertEqual(loaded.rawLogSummary.byteCount, 1)
        XCTAssertEqual(loaded.rawLogSummary.localState, .removed)
        XCTAssertEqual(loaded.rawLogSummary.manifestDigest, "digest")
        XCTAssertEqual(loaded.rawLogSummary.macImportReceipt, receipt)
        XCTAssertTrue(loaded.rawLogSummary.isDurablyImportedByMac)
        XCTAssertTrue(try repository.entries(for: session.id).isEmpty)
    }

    /// 同じアカウントのRawログを登録車両IDごとにセッション境界付きで抽出します。
    ///
    /// 責務: 将来の学習入力が別車両のRawレコードを混在させず取得できることを確認します。
    func testVehicleScopedEntriesExcludeOtherVehicles() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let firstVehicle = VehicleProfile(vin: "FIRST-VIN", name: "First BRZ")
        let secondVehicle = VehicleProfile(vin: "SECOND-VIN", name: "Second BRZ")
        var firstSession = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 100),
            vehicle: ConnectionSessionVehicle(profile: firstVehicle)
        )
        var secondSession = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 200),
            vehicle: ConnectionSessionVehicle(profile: secondVehicle)
        )
        try repository.save(firstSession)
        try repository.save(secondSession)
        try repository.append(
            OBDRawResponseObservation(
                observedAt: Date(timeIntervalSince1970: 101),
                batchElapsedNanoseconds: 1_000_000,
                request: OBDPIDRequest(service: 0x01, pid: 0x0C),
                payload: [0x01]
            ),
            to: firstSession.id
        )
        try repository.append(
            OBDRawResponseObservation(
                observedAt: Date(timeIntervalSince1970: 201),
                batchElapsedNanoseconds: 2_000_000,
                request: OBDPIDRequest(service: 0x01, pid: 0x0D),
                payload: [0x02]
            ),
            to: secondSession.id
        )
        firstSession.endedAt = Date(timeIntervalSince1970: 110)
        firstSession.endReason = .userDisconnected
        secondSession.endedAt = Date(timeIntervalSince1970: 210)
        secondSession.endReason = .userDisconnected
        try repository.save(firstSession)
        try repository.save(secondSession)

        let extracted = try repository.entries(for: firstVehicle.id, accountIdentifier: "account")

        XCTAssertEqual(extracted.map(\.vehicleID), [firstVehicle.id])
        XCTAssertEqual(extracted.map(\.sessionID), [firstSession.id])
        XCTAssertEqual(extracted.map(\.sessionStartedAt), [Date(timeIntervalSince1970: 100)])
        XCTAssertEqual(extracted.map(\.entry.payload), [[0x01]])
        XCTAssertTrue(try repository.entries(for: firstVehicle.id, accountIdentifier: "other-account").isEmpty)
    }

    /// アカウント削除は対象アカウントのセッションと全Rawログだけを削除します。
    ///
    /// 責務: ローカル運転データ全削除が別アカウントを保持しつつ子RawログをCascade削除することを確認します。
    func testDeleteSessionsRemovesAccountHistoryAndRawEntries() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let deletedSession = ConnectionSession(accountIdentifier: "delete-account", startedAt: Date(timeIntervalSince1970: 100))
        let retainedSession = ConnectionSession(accountIdentifier: "retain-account", startedAt: Date(timeIntervalSince1970: 200))
        try repository.save(deletedSession)
        try repository.save(retainedSession)
        try repository.append(
            OBDRawResponseObservation(
                observedAt: Date(timeIntervalSince1970: 101),
                batchElapsedNanoseconds: 1_000_000,
                request: OBDPIDRequest(service: 0x01, pid: 0x0C),
                payload: [0x12, 0x34]
            ),
            to: deletedSession.id
        )
        try repository.append(
            OBDRawResponseObservation(
                observedAt: Date(timeIntervalSince1970: 201),
                batchElapsedNanoseconds: 2_000_000,
                request: OBDPIDRequest(service: 0x01, pid: 0x0D),
                payload: [0x56]
            ),
            to: retainedSession.id
        )

        try repository.deleteSessions(for: "delete-account")

        XCTAssertTrue(try repository.sessions(for: "delete-account").isEmpty)
        XCTAssertTrue(try repository.entries(for: deletedSession.id).isEmpty)
        XCTAssertEqual(try repository.sessions(for: "retain-account").map(\.id), [retainedSession.id])
        XCTAssertEqual(try repository.entries(for: retainedSession.id).map(\.payload), [[0x56]])
    }
}
