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
            vehicle: ConnectionSessionVehicle(profile: vehicle),
            acquisitionDevice: ConnectionSessionAcquisitionDevice(platform: .macOS, name: "MacBook Pro")
        )
        session.endedAt = Date(timeIntervalSince1970: 200)
        session.endReason = .userDisconnected
        session.startingOdometerKilometers = 98_765.4
        session.endingOdometerKilometers = 98_767.9
        session.distanceSourceModelCode = "ZD8"

        try repository.save(session)
        let loaded = try XCTUnwrap(repository.sessions(for: "account").first)

        XCTAssertEqual(loaded, session)
        XCTAssertEqual(loaded.status, .completed)
        XCTAssertEqual(loaded.acquisitionDevice, session.acquisitionDevice)
        XCTAssertEqual(loaded.distanceSourceModelCode, "ZD8")
        XCTAssertEqual(try XCTUnwrap(loaded.recordedDistanceKilometers), 2.5, accuracy: 0.000_1)
        XCTAssertTrue(try repository.sessions(for: "different-account").isEmpty)
    }

    /// ユーザー確認済み停止を元終了理由と独立して永続化します。
    ///
    /// 責務: 1件の確認済み接続喪失セッションが終了理由と確認結果を欠落なく往復することを確認します。
    func testSaveAndLoadPreservesUserInitiatedStopReview() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        session.endedAt = Date(timeIntervalSince1970: 200)
        session.endReason = .connectionLost
        session.stopReviewDecision = .userInitiated

        try repository.save(session)
        let loaded = try XCTUnwrap(repository.sessions(for: "account").first)

        XCTAssertEqual(loaded.endReason, .connectionLost)
        XCTAssertEqual(loaded.stopReviewDecision, .userInitiated)
        XCTAssertEqual(loaded.status, .completed)
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

    /// 同一Manifestの再受信では明示的に除去したローカルRawログを復元しません。
    ///
    /// 責務: iPhoneのローカル除去状態とMac受領証が後続同期でも保持されることを確認します。
    func testRepeatedTransferImportPreservesRemovedLocalPayloadState() throws {
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
        let uploadedSession = try XCTUnwrap(repository.sessions(for: "account").first)
        let uploadedEntries = try repository.entries(for: session.id)
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: uploadedSession, entries: uploadedEntries),
            manifestDigest: "digest"
        )
        try repository.markCloudUploaded(sessionID: session.id, manifestDigest: "digest")
        let receipt = ConnectionSessionMacImportReceipt(
            deviceID: "mac-installation",
            deviceName: "Garage Mac",
            importedAt: Date(timeIntervalSince1970: 103),
            manifestDigest: "digest"
        )
        try repository.markMacImported(receipt, sessionID: session.id)
        try repository.removeLocalEntries(for: session.id)

        try repository.importVerifiedTransfer(transfer)

        let loaded = try XCTUnwrap(repository.sessions(for: "account").first)
        XCTAssertEqual(loaded.rawLogSummary.localState, .removed)
        XCTAssertEqual(loaded.rawLogSummary.macImportReceipt, receipt)
        XCTAssertTrue(try repository.entries(for: session.id).isEmpty)
    }

    /// 同一Manifestの空ログセッション再受信では既存のMac受領証を保持します。
    ///
    /// 責務: メタデータのみのセッション取込が冪等で受領証を再生成不要にすることを確認します。
    func testRepeatedMetadataOnlyTransferImportPreservesMacReceipt() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        session.endedAt = Date(timeIntervalSince1970: 102)
        session.endReason = .userDisconnected
        try repository.save(session)
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: session, entries: []),
            manifestDigest: "digest"
        )
        try repository.markCloudUploaded(sessionID: session.id, manifestDigest: "digest")
        let receipt = ConnectionSessionMacImportReceipt(
            deviceID: "mac-installation",
            deviceName: "Garage Mac",
            importedAt: Date(timeIntervalSince1970: 103),
            manifestDigest: "digest"
        )
        try repository.markMacImported(receipt, sessionID: session.id)

        try repository.importVerifiedTransfer(transfer)

        let loaded = try XCTUnwrap(repository.sessions(for: "account").first)
        XCTAssertEqual(loaded.rawLogSummary.localState, .empty)
        XCTAssertEqual(loaded.rawLogSummary.macImportReceipt, receipt)
        XCTAssertTrue(try repository.entries(for: session.id).isEmpty)
    }

    /// 同一Manifestの再受信ではJSON日時精度差があってもローカルRawログを保持します。
    ///
    /// 責務: 検証済みManifestが同じ転送のミリ秒丸め差を内容競合として扱わないことを確認します。
    func testRepeatedTransferWithSameManifestPreservesHigherPrecisionLocalContent() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        var session = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 100.123_456)
        )
        try repository.save(session)
        try repository.append(
            OBDRawResponseObservation(
                observedAt: Date(timeIntervalSince1970: 101.123_456),
                batchElapsedNanoseconds: 2_000_000,
                request: OBDPIDRequest(service: 0x01, pid: 0x0D),
                payload: [0x32]
            ),
            to: session.id
        )
        session.endedAt = Date(timeIntervalSince1970: 102.123_456)
        session.endReason = .userDisconnected
        try repository.save(session)
        let localSession = try XCTUnwrap(repository.sessions(for: "account").first)
        let localEntries = try repository.entries(for: session.id)
        try repository.markCloudUploaded(sessionID: session.id, manifestDigest: "same-manifest")
        var roundedSession = localSession
        roundedSession.endedAt = Date(timeIntervalSince1970: 102.123)
        var roundedEntry = try XCTUnwrap(localEntries.first)
        roundedEntry = ConnectionSessionRawLogEntry(
            sequence: roundedEntry.sequence,
            observedAt: Date(timeIntervalSince1970: 101.123),
            batchElapsedNanoseconds: roundedEntry.batchElapsedNanoseconds,
            service: roundedEntry.service,
            pid: roundedEntry.pid,
            payload: roundedEntry.payload
        )
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: roundedSession, entries: [roundedEntry]),
            manifestDigest: "same-manifest"
        )

        try repository.importVerifiedTransfer(transfer)

        XCTAssertEqual(try repository.entries(for: session.id), localEntries)
        XCTAssertEqual(try XCTUnwrap(repository.sessions(for: "account").first).endedAt, localSession.endedAt)
    }

    /// 同一Manifest再取込時に欠落した車両と取得端末メタデータを復旧します。
    ///
    /// 責務: ローカル列だけが欠落した同期済みセッションを検証済みPayloadから非破壊で自己修復できることを確認します。
    func testRepeatedTransferImportRepairsMissingVehicleAndAcquisitionDevice() throws {
        let queue = try DatabaseQueue()
        let repository = try GRDBConnectionSessionRepository(databaseQueue: queue)
        let vehicle = ConnectionSessionVehicle(
            id: VehicleID(),
            name: "BRZ",
            displayIdentifier: "ZD8"
        )
        let acquisitionDevice = ConnectionSessionAcquisitionDevice(platform: .iPhone, name: "iPhone 17 Pro")
        var session = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 100),
            vehicle: vehicle,
            acquisitionDevice: acquisitionDevice
        )
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: session, entries: []),
            manifestDigest: "digest"
        )
        try repository.importVerifiedTransfer(transfer)
        try queue.write { database in
            try database.execute(
                sql: "UPDATE connection_sessions SET vehicleID = NULL, vehicleName = NULL, vehicleDisplayIdentifier = NULL, acquisitionPlatform = NULL, acquisitionDeviceName = NULL WHERE id = ?",
                arguments: [session.id.rawValue.uuidString.lowercased()]
            )
        }

        try repository.importVerifiedTransfer(transfer)

        let repaired = try XCTUnwrap(repository.sessions(for: "account").first)
        XCTAssertEqual(repaired.vehicle, vehicle)
        XCTAssertEqual(repaired.acquisitionDevice, acquisitionDevice)
        XCTAssertEqual(repaired.rawLogSummary.cloudState, .uploaded)
        XCTAssertEqual(repaired.rawLogSummary.manifestDigest, "digest")
    }

    /// 同じRawログを持つ旧形式Manifestを検証済み転送Manifestへ整合させます。
    ///
    /// 責務: 端末固有同期状態だけでDigestが変わった既存セッションを内容競合として拒否しないことを確認します。
    func testEquivalentTransferReconcilesStaleManifestWithoutReplacingRawEntries() throws {
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
        let transferredSession = try XCTUnwrap(repository.sessions(for: "account").first)
        let entries = try repository.entries(for: session.id)
        try repository.markCloudUploaded(sessionID: session.id, manifestDigest: "stale-local-manifest")
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: transferredSession, entries: entries),
            manifestDigest: "verified-remote-manifest"
        )

        try repository.importVerifiedTransfer(transfer)

        let reconciled = try XCTUnwrap(repository.sessions(for: "account").first)
        XCTAssertEqual(reconciled.rawLogSummary.manifestDigest, "verified-remote-manifest")
        XCTAssertEqual(reconciled.rawLogSummary.cloudState, .uploaded)
        XCTAssertEqual(try repository.entries(for: session.id), entries)
    }

    /// Rawログが同じでも終了情報が異なる転送を整合性競合として拒否します。
    ///
    /// 責務: Manifest救済が実際の保存済みセッション内容差を上書きしないことを確認します。
    func testEquivalentRawEntriesDoNotHideArchivedMetadataConflict() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        session.endedAt = Date(timeIntervalSince1970: 102)
        session.endReason = .userDisconnected
        try repository.save(session)
        try repository.markCloudUploaded(sessionID: session.id, manifestDigest: "local-manifest")
        var conflicting = session
        conflicting.endReason = .connectionLost
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: conflicting, entries: []),
            manifestDigest: "remote-manifest"
        )

        XCTAssertThrowsError(try repository.importVerifiedTransfer(transfer)) { error in
            XCTAssertEqual(error as? ConnectionSessionRepositoryError, .integrityConflict)
        }
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
