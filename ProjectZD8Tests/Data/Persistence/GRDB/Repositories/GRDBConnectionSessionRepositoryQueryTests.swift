import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionRepository` の初期化と読取系メソッドを分岐・境界単位で検証します。
@MainActor
final class GRDBConnectionSessionRepositoryQueryTests: XCTestCase {
    // MARK: - init(databaseQueue:)

    /// 書込み不能なDBではMigrationに失敗して `unavailable` を返します。
    ///
    /// 責務: 読取専用の空DBへ生成した場合にMigration失敗が `unavailable` へ変換されることを確認します。
    func testInitThrowsUnavailableWhenMigrationCannotWrite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("empty.sqlite").path
        XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: Data()))
        var configuration = Configuration()
        configuration.readonly = true
        let readonlyQueue = try DatabaseQueue(path: path, configuration: configuration)

        assertThrowsError(ConnectionSessionAcquisitionRepositoryError.unavailable) {
            _ = try GRDBConnectionSessionRepository(databaseQueue: readonlyQueue)
        }
        XCTAssertFalse(try readonlyQueue.read { try $0.tableExists("connection_sessions") })
    }

    // MARK: - sessions(for:)

    /// 一覧は開始日時の新しい順で、指定アカウントだけを返します。
    ///
    /// 責務: アカウント絞り込みと開始日時降順の並びを確認します。
    func testSessionsAreFilteredByAccountAndSortedNewestFirst() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let oldest = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        let newest = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 300))
        let middle = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 200))
        let foreign = ConnectionSession(accountIdentifier: "other", startedAt: Date(timeIntervalSince1970: 400))
        for session in [oldest, newest, middle, foreign] {
            try fixtures.repository.save(session)
        }

        let loaded = try fixtures.repository.sessions(for: "account")

        XCTAssertEqual(loaded.map(\.id), [newest.id, middle.id, oldest.id])
        XCTAssertTrue(try fixtures.repository.sessions(for: "unknown").isEmpty)
    }

    /// 保存済みの未知の保管状態を持つ行は一覧取得時に `DatabaseError` になります。
    ///
    /// 責務: Domainへ復元できない行を空や成功へ潰さず失敗させることを確認します。
    func testSessionsThrowDatabaseErrorWhenStoredRowCannotBeRestored() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = ConnectionSession(accountIdentifier: "account")
        try fixtures.repository.save(session)
        try fixtures.updateSessionRow([Column("localRawState").set(to: "corrupted")], id: session.id)

        XCTAssertThrowsError(try fixtures.repository.sessions(for: "account")) { error in
            XCTAssertTrue(error is DatabaseError, "実際のエラー: \(error)")
        }
    }

    /// 未知の終了原因を持つ行も一覧取得時に失敗します。
    ///
    /// 責務: 終了原因の復元失敗が一覧全体のエラーになることを確認します。
    func testSessionsThrowDatabaseErrorWhenEndReasonIsUnknown() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 0)
        try fixtures.updateSessionRow([Column("endReason").set(to: "unknownReason")], id: session.id)

        XCTAssertThrowsError(try fixtures.repository.sessions(for: "account")) { error in
            XCTAssertTrue(error is DatabaseError, "実際のエラー: \(error)")
        }
    }

    /// 取得中のRaw子行がないのに概要が `available` の行は件数と容量を0へ補正します。
    ///
    /// 責務: 子行集計が空の場合に壊れた概要列の件数・容量を実態の0へ置き換えることを確認します。
    func testSessionsCorrectStaleSummaryToZeroWhenNoRawRowsExist() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = ConnectionSession(accountIdentifier: "account")
        try fixtures.repository.save(session)
        try fixtures.updateSessionRow(
            [
                Column("rawRecordCount").set(to: 99),
                Column("rawByteCount").set(to: 999),
                Column("localRawState").set(to: "available")
            ],
            id: session.id
        )

        // 前提: 壊れた概要値が実際にDBへ書き込まれていること(更新が空振りしても通るテストを防ぐ)。
        let stored = try fixtures.storedRecord(session.id)
        XCTAssertEqual(stored.rawRecordCount, 99)
        XCTAssertEqual(stored.rawByteCount, 999)
        XCTAssertEqual(stored.localRawState, "available")

        let loaded = try XCTUnwrap(fixtures.repository.sessions(for: "account").first)

        XCTAssertEqual(loaded.rawLogSummary.recordCount, 0)
        XCTAssertEqual(loaded.rawLogSummary.byteCount, 0)
    }

    /// ローカルRaw除去済みの行は保存済み概要をそのまま返します。
    ///
    /// 責務: `removed` では子行集計で上書きせず、保存された件数・容量を維持することを確認します。
    func testSessionsKeepStoredSummaryWhenLocalRawIsRemoved() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = ConnectionSession(accountIdentifier: "account")
        try fixtures.repository.save(session)
        try fixtures.updateSessionRow(
            [
                Column("rawRecordCount").set(to: 7),
                Column("rawByteCount").set(to: 70),
                Column("localRawState").set(to: "removed")
            ],
            id: session.id
        )

        let loaded = try XCTUnwrap(fixtures.repository.sessions(for: "account").first)

        XCTAssertEqual(loaded.rawLogSummary.recordCount, 7)
        XCTAssertEqual(loaded.rawLogSummary.byteCount, 70)
        XCTAssertEqual(loaded.rawLogSummary.localState, .removed)
    }

    // MARK: - entries(for:)

    /// セッション別のRawログを `sequence` 昇順で返し、他セッションを含めません。
    ///
    /// 責務: 1件のセッションIDに属する子行だけを記録順に復元することを確認します。
    func testEntriesReturnOnlyRequestedSessionInSequenceOrder() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let target = try fixtures.seedEndedSession(rawCount: 3)
        try fixtures.seedEndedSession(rawCount: 2)

        let entries = try fixtures.repository.entries(for: target.id)

        XCTAssertEqual(entries.map(\.sequence), [0, 1, 2])
        XCTAssertEqual(entries.map(\.payload), [[0], [1], [2]])
        XCTAssertTrue(try fixtures.repository.entries(for: ConnectionSessionID()).isEmpty)
    }

    /// 範囲外のService値を持つRaw行は `integrityConflict` になります。
    ///
    /// 責務: Domainへ復元できないRaw行を黙って捨てず整合性エラーにすることを確認します。
    func testEntriesThrowIntegrityConflictWhenServiceIsOutOfRange() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 0)
        try fixtures.insertRawRow(session.id, sequence: 0, service: 256, elapsed: 1)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            _ = try fixtures.repository.entries(for: session.id)
        }
    }

    // MARK: - entryCount(for:)

    /// 件数はセッションごとのRaw行数で、不明セッションは0です。
    ///
    /// 責務: 他セッションを数えず、行がない場合に0を返すことを確認します。
    func testEntryCountCountsOnlyRequestedSession() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let target = try fixtures.seedEndedSession(rawCount: 3)
        let empty = try fixtures.seedEndedSession(rawCount: 0)
        try fixtures.seedEndedSession(rawCount: 5)

        XCTAssertEqual(try fixtures.repository.entryCount(for: target.id), 3)
        XCTAssertEqual(try fixtures.repository.entryCount(for: empty.id), 0)
        XCTAssertEqual(try fixtures.repository.entryCount(for: ConnectionSessionID()), 0)
    }

    /// ローカルRaw除去後の件数は0です。
    ///
    /// 責務: 概要列ではなく実際の子行数を数えることを確認します。
    func testEntryCountIsZeroAfterLocalRemoval() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 2)

        try fixtures.repository.removeLocalEntries(for: session.id)

        XCTAssertEqual(try fixtures.repository.entryCount(for: session.id), 0)
        XCTAssertEqual(try fixtures.storedRecord(session.id).rawRecordCount, 2)
    }

    // MARK: - entries(for:after:limit:)

    /// 先頭ページ(カーソルなし)は `limit` 件までを昇順で返します。
    ///
    /// 責務: `after == nil` で先頭から上限件数を取得することを確認します。
    func testPagedEntriesWithoutCursorReturnFirstLimitEntries() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 5)

        let page = try fixtures.repository.entries(for: session.id, after: nil, limit: 3)

        XCTAssertEqual(page.map(\.sequence), [0, 1, 2])
    }

    /// カーソルは指定sequenceより大きい行だけを返します(排他的)。
    ///
    /// 責務: 先頭・中間・末尾直前・末尾・範囲外のカーソル境界を確認します。
    func testPagedEntriesCursorIsExclusiveAtStartMiddleAndEnd() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 5)
        let repository = fixtures.repository

        XCTAssertEqual(try repository.entries(for: session.id, after: -1, limit: 10).map(\.sequence), [0, 1, 2, 3, 4])
        XCTAssertEqual(try repository.entries(for: session.id, after: 0, limit: 10).map(\.sequence), [1, 2, 3, 4])
        XCTAssertEqual(try repository.entries(for: session.id, after: 2, limit: 10).map(\.sequence), [3, 4])
        XCTAssertEqual(try repository.entries(for: session.id, after: 3, limit: 10).map(\.sequence), [4])
        XCTAssertTrue(try repository.entries(for: session.id, after: 4, limit: 10).isEmpty)
        XCTAssertTrue(try repository.entries(for: session.id, after: 100, limit: 10).isEmpty)
    }

    /// 上限件数は0・負数・1・総数ちょうど・総数超過で期待件数だけ返します。
    ///
    /// 責務: `limit` の境界値(0未満は0件扱いを含む)を確認します。
    func testPagedEntriesLimitBoundaries() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 5)
        let repository = fixtures.repository

        XCTAssertTrue(try repository.entries(for: session.id, after: nil, limit: 0).isEmpty)
        XCTAssertTrue(try repository.entries(for: session.id, after: nil, limit: -1).isEmpty)
        XCTAssertEqual(try repository.entries(for: session.id, after: nil, limit: 1).map(\.sequence), [0])
        XCTAssertEqual(try repository.entries(for: session.id, after: nil, limit: 4).map(\.sequence), [0, 1, 2, 3])
        XCTAssertEqual(try repository.entries(for: session.id, after: nil, limit: 5).map(\.sequence), [0, 1, 2, 3, 4])
        XCTAssertEqual(try repository.entries(for: session.id, after: nil, limit: 6).map(\.sequence), [0, 1, 2, 3, 4])
    }

    /// カーソルを進めながらページングすると全件を重複なく復元できます。
    ///
    /// 責務: 前ページ末尾のsequenceを次ページのカーソルとして使うと欠落・重複がないことを確認します。
    func testPagedEntriesTraversalCoversAllEntriesExactlyOnce() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 5)
        var collected: [Int64] = []
        var cursor: Int64?

        let maxPages = 6
        var pageCount = 0
        while pageCount < maxPages {
            pageCount += 1
            let page = try fixtures.repository.entries(for: session.id, after: cursor, limit: 2)
            if page.isEmpty { break }
            collected.append(contentsOf: page.map(\.sequence))
            cursor = page.last?.sequence
        }
        XCTAssertLessThan(pageCount, maxPages, "ページングが終了しません(カーソルが進んでいない可能性)")

        XCTAssertEqual(collected, [0, 1, 2, 3, 4])
    }

    /// 不明セッションと他セッションの行は空配列で、混ざりません。
    ///
    /// 責務: セッションID絞り込みがページ取得にも効くことを確認します。
    func testPagedEntriesAreScopedToSession() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let target = try fixtures.seedEndedSession(rawCount: 2)
        try fixtures.seedEndedSession(rawCount: 3)

        XCTAssertEqual(try fixtures.repository.entries(for: target.id, after: nil, limit: 10).map(\.payload), [[0], [1]])
        XCTAssertTrue(try fixtures.repository.entries(for: ConnectionSessionID(), after: nil, limit: 10).isEmpty)
    }

    /// ページ取得でもDomainへ復元できないRaw行は `integrityConflict` になります。
    ///
    /// 責務: 経過時間が負の不正行を整合性エラーにすることを確認します。
    func testPagedEntriesThrowIntegrityConflictWhenElapsedIsNegative() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 0)
        try fixtures.insertRawRow(session.id, sequence: 0, service: 1, elapsed: -1)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            _ = try fixtures.repository.entries(for: session.id, after: nil, limit: 10)
        }
    }

    // MARK: - entries(for:accountIdentifier:)

    /// 車両別抽出は開始日時、同時刻はセッションIDの順で、各セッション内はsequence順です。
    ///
    /// 責務: 複数セッションの安定した並びとセッション境界情報を確認します。
    func testVehicleEntriesAreOrderedByStartedAtThenSessionID() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let vehicle = ConnectionSessionVehicle(profile: VehicleProfile(vin: "VIN-ORDER", name: "BRZ"))
        let lowID = ConnectionSessionID(rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
        let highID = ConnectionSessionID(rawValue: try XCTUnwrap(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")))
        let laterID = ConnectionSessionID(rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002")))
        for (id, startedAt) in [(highID, 100.0), (laterID, 200.0), (lowID, 100.0)] {
            try fixtures.repository.save(
                ConnectionSession(
                    id: id,
                    accountIdentifier: "account",
                    startedAt: Date(timeIntervalSince1970: startedAt),
                    vehicle: vehicle
                )
            )
            try fixtures.repository.append(GRDBConnectionSessionRepositoryFixtures.observation(payload: [0xA0]), to: id)
            try fixtures.repository.append(GRDBConnectionSessionRepositoryFixtures.observation(payload: [0xA1]), to: id)
        }

        let extracted = try fixtures.repository.entries(for: vehicle.id, accountIdentifier: "account")

        XCTAssertEqual(extracted.map(\.sessionID), [lowID, lowID, highID, highID, laterID, laterID])
        XCTAssertEqual(extracted.map(\.entry.sequence), [0, 1, 0, 1, 0, 1])
        XCTAssertEqual(extracted.map(\.entry.payload), [[0xA0], [0xA1], [0xA0], [0xA1], [0xA0], [0xA1]])
        XCTAssertEqual(extracted.map(\.vehicleID), Array(repeating: vehicle.id, count: 6))
        XCTAssertEqual(extracted.last?.sessionStartedAt, Date(timeIntervalSince1970: 200))
    }

    /// Rawログがない車両セッションは空配列、車両未登録も空配列です。
    ///
    /// 責務: 該当セッションが無い・子行が無い場合に空を返し、エラーにしないことを確認します。
    func testVehicleEntriesAreEmptyWithoutRawRowsOrMatchingSessions() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let vehicle = ConnectionSessionVehicle(profile: VehicleProfile(vin: "VIN-EMPTY", name: "BRZ"))
        try fixtures.repository.save(ConnectionSession(accountIdentifier: "account", vehicle: vehicle))

        XCTAssertTrue(try fixtures.repository.entries(for: vehicle.id, accountIdentifier: "account").isEmpty)
        XCTAssertTrue(try fixtures.repository.entries(for: VehicleID(), accountIdentifier: "account").isEmpty)
    }

    /// 車両のセッション行が復元できない場合は `integrityConflict` になります。
    ///
    /// 責務: 不正なCloud状態を持つ行を学習入力へ混ぜず整合性エラーにすることを確認します。
    func testVehicleEntriesThrowIntegrityConflictWhenSessionRowIsInvalid() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let vehicle = ConnectionSessionVehicle(profile: VehicleProfile(vin: "VIN-BAD", name: "BRZ"))
        let session = ConnectionSession(accountIdentifier: "account", vehicle: vehicle)
        try fixtures.repository.save(session)
        try fixtures.updateSessionRow([Column("cloudSyncState").set(to: "corrupted")], id: session.id)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            _ = try fixtures.repository.entries(for: vehicle.id, accountIdentifier: "account")
        }
    }

    /// 車両IDだけ残り名称列が欠けた行は車両を復元できず `integrityConflict` になります。
    ///
    /// 責務: セッションの車両が要求車両IDと一致しない場合に別車両として混入させないことを確認します。
    func testVehicleEntriesThrowIntegrityConflictWhenVehicleCannotBeRestored() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let vehicle = ConnectionSessionVehicle(profile: VehicleProfile(vin: "VIN-HALF", name: "BRZ"))
        let session = ConnectionSession(accountIdentifier: "account", vehicle: vehicle)
        try fixtures.repository.save(session)
        try fixtures.writeIgnoringCheckConstraints { database in
            try database.execute(
                sql: "UPDATE connection_sessions SET vehicleName = NULL WHERE id = ?",
                arguments: [session.id.rawValue.uuidString.lowercased()]
            )
        }

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            _ = try fixtures.repository.entries(for: vehicle.id, accountIdentifier: "account")
        }
    }

    /// 車両セッション配下の不正Raw行は `integrityConflict` になります。
    ///
    /// 責務: 子Rawログが復元できない場合に一部だけ返さず失敗することを確認します。
    func testVehicleEntriesThrowIntegrityConflictWhenRawRowIsInvalid() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let vehicle = ConnectionSessionVehicle(profile: VehicleProfile(vin: "VIN-RAW", name: "BRZ"))
        let session = ConnectionSession(accountIdentifier: "account", vehicle: vehicle)
        try fixtures.repository.save(session)
        try fixtures.insertRawRow(session.id, sequence: 0, service: 1, elapsed: -5)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            _ = try fixtures.repository.entries(for: vehicle.id, accountIdentifier: "account")
        }
    }
}
