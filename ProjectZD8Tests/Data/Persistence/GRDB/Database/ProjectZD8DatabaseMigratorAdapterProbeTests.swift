import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `release_v1_add_connection_session_acquisition_adapter_probe` の既存行保全、CHECK制約、不変性triggerを検証します。
///
/// SQLは固定リテラルと引数バインドだけで組み立てます。
final class ProjectZD8DatabaseMigratorAdapterProbeTests: XCTestCase {
    /// アダプター判定列を追加する直前のMigration識別子です。
    private static let previousMigration = "release_v1_add_connection_session_observed_vin"

    /// 未封印のmanifest行を、アダプター判定2列を指定して直接挿入します。
    ///
    /// 責務: 既存の必須列を固定値にした1件の `connection_session_acquisition_manifests` 行を追加します。
    /// - Parameters:
    ///   - database: 書込み中の接続。
    ///   - chip: チップ種別列の保存値。
    ///   - outcome: ATMA判定列の保存値。
    /// - Throws: SQLite書込み失敗(制約違反を含む)。
    private func insertManifest(_ database: Database, chip: String?, outcome: String?) throws {
        try database.execute(
            sql: """
                INSERT INTO connection_session_acquisition_manifests
                (sessionID, manifestVersion, applicationMarketingVersion, applicationBuildVersion, schemaContractVersion,
                 pollingPolicyVersion, acquisitionPlatform, modelInputManifestVersion, adapterChipFamily,
                 adapterMonitorProbeOutcome, isSealed)
                VALUES (?, 1, 'fixture', '1', 1, 1, 'macOS', 1, ?, ?, 0)
                """,
            arguments: [SegmentationSchemaFixtures.sessionA, chip, outcome]
        )
    }

    /// 旧スキーマでも存在する列だけで親セッション行を挿入します。
    ///
    /// 責務: Migration途中のDBへ1件の `connection_sessions` 行を固定SQLで追加します。
    /// - Parameter database: 書込み中の接続。
    /// - Throws: SQLite書込み失敗。
    private func insertLegacySession(_ database: Database) throws {
        try database.execute(
            sql: "INSERT INTO connection_sessions (id, accountIdentifier, startedAt) VALUES (?, 'account', ?)",
            arguments: [SegmentationSchemaFixtures.sessionA, Date(timeIntervalSince1970: 90)]
        )
    }

    /// 旧スキーマ(2列追加前)の列だけで未封印manifestとPID・開始境界を挿入し、封印します。
    ///
    /// 責務: Migration適用前に正規の手順で保存された1件の封印済み取得証跡を再現します。
    /// - Parameter database: 書込み中の接続。
    /// - Throws: SQLite書込み失敗。
    private func insertLegacySealedManifest(_ database: Database) throws {
        let key = SegmentationSchemaFixtures.sessionA
        try database.execute(
            sql: """
                INSERT INTO connection_session_acquisition_manifests
                (sessionID, manifestVersion, applicationMarketingVersion, applicationBuildVersion, schemaContractVersion,
                 pollingPolicyVersion, acquisitionPlatform, modelInputManifestVersion, isSealed)
                VALUES (?, 1, 'fixture', '1', 1, 1, 'macOS', 1, 0)
                """,
            arguments: [key]
        )
        try database.execute(
            sql: """
                INSERT INTO connection_session_acquisition_pid_definitions
                (sessionID, service, pid, capabilitySupport, isCollectionEnabled, definitionRevision, requiredByteCount,
                 formulaCanonicalizationVersion, formulaExpression, unit, validityRangeKind, minimumValue, maximumValue)
                VALUES (?, 1, 12, 'supported', 1, 1, 2, 1, 'A', 'rpm', 'notDeclared', NULL, NULL)
                """,
            arguments: [key]
        )
        try database.execute(
            sql: "INSERT INTO connection_session_acquisition_ordered_pids (sessionID, ordinal, service, pid) VALUES (?, 0, 1, 12)",
            arguments: [key]
        )
        try startAndSeal(database)
    }

    /// 開始境界を追加してmanifestを封印します。
    ///
    /// 責務: 封印遷移の前提となる開始境界を1件追加し、`isSealed` だけを1へ更新します。
    /// - Parameter database: 書込み中の接続。
    /// - Throws: SQLite書込み失敗(trigger拒否を含む)。
    private func startAndSeal(_ database: Database) throws {
        try database.execute(
            sql: """
                INSERT INTO connection_session_acquisition_raw_boundaries
                (sessionID, eventKind, occurredAtMicroseconds, endReason) VALUES (?, 'started', 100000000, NULL)
                """,
            arguments: [SegmentationSchemaFixtures.sessionA]
        )
        try database.execute(
            sql: "UPDATE connection_session_acquisition_manifests SET isSealed = 1 WHERE sessionID = ?",
            arguments: [SegmentationSchemaFixtures.sessionA]
        )
    }

    /// 指定SQLでmanifest行を更新します。
    ///
    /// 責務: 1件の固定UPDATE文を対象セッションへ引数バインドで実行します。
    /// - Parameters:
    ///   - database: 書込み中の接続。
    ///   - sql: 対象セッションIDを1個の引数として受け取る固定UPDATE文。
    /// - Throws: SQLite更新失敗(trigger拒否を含む)。
    private func update(_ database: Database, _ sql: String) throws {
        try database.execute(sql: sql, arguments: [SegmentationSchemaFixtures.sessionA])
    }

    /// manifest行のアダプター判定2列と封印状態を読みます。
    ///
    /// 責務: 1件の行の保存値を固定SQLで返します。
    /// - Parameter queue: 読取対象のDB Queue。
    /// - Returns: 読み出した行。
    /// - Throws: SQLite読込失敗、または行が無い場合の `XCTUnwrap` 失敗。
    private func storedRow(_ queue: DatabaseQueue) throws -> Row {
        let row = try queue.read { database in
            try Row.fetchOne(
                database,
                sql: """
                    SELECT adapterChipFamily, adapterMonitorProbeOutcome, isSealed
                    FROM connection_session_acquisition_manifests WHERE sessionID = ?
                    """,
                arguments: [SegmentationSchemaFixtures.sessionA]
            )
        }
        return try XCTUnwrap(row)
    }

    // MARK: - upgrade

    /// 適用前から存在したmanifest行は2列ともNULLで読め、Repositoryの証跡は `nil` です。
    ///
    /// 責務: 旧スキーマで封印済みの取得証跡がMigration後も失敗せず、証跡なしとして復元されることを確認します。
    func testUpgradeKeepsLegacyManifestReadableWithNilEvidence() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue, upTo: Self.previousMigration)
        try queue.write { database in
            try insertLegacySession(database)
            try insertLegacySealedManifest(database)
        }

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        let row = try storedRow(queue)
        XCTAssertEqual(row["adapterChipFamily"] as DatabaseValue, .null)
        XCTAssertEqual(row["adapterMonitorProbeOutcome"] as DatabaseValue, .null)
        XCTAssertEqual(row["isSealed"] as Int, 1)
        let id = ConnectionSessionID(rawValue: try XCTUnwrap(UUID(uuidString: SegmentationSchemaFixtures.sessionA)))
        let manifest = try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue).manifest(for: id)
        XCTAssertNil(manifest.adapterProbeEvidence)
        XCTAssertEqual(manifest.orderedRequestedPIDs?.requests, [OBDPIDRequest(service: 1, pid: 12)])
    }

    // MARK: - CHECK constraint

    /// 仕様の安定文字列(チップ種別のみ、または判定結果付き)は直接INSERTで受け付けます。
    ///
    /// 責務: 制約が正当な保存値まで拒否しない(拒否テストが常に失敗する状態でない)ことを確認します。
    func testCheckAcceptsStableStringsAndChipWithoutOutcome() throws {
        for chip in ["stn", "elm327Genuine", "elm327Clone", "unknown"] {
            let fixtures = try SegmentationSchemaFixtures()
            try fixtures.queue.write { database in
                try fixtures.insertSession(database)
                try insertManifest(database, chip: chip, outcome: nil)
            }
            XCTAssertEqual(try storedRow(fixtures.queue)["adapterChipFamily"] as String?, chip)
        }
        for outcome in ["framesReceived", "unsupported", "bufferFull", "silent", "busError", "stopped"] {
            let fixtures = try SegmentationSchemaFixtures()
            try fixtures.queue.write { database in
                try fixtures.insertSession(database)
                try insertManifest(database, chip: "stn", outcome: outcome)
            }
            XCTAssertEqual(try storedRow(fixtures.queue)["adapterMonitorProbeOutcome"] as String?, outcome)
        }
    }

    /// 未知のチップ種別文字列は拒否されます。
    ///
    /// 責務: 未定義値と、大文字小文字だけ異なる値・空文字が保存できないことを確認します。
    func testCheckRejectsUnknownChipFamilyString() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }

        for chip in ["elm327", "STN", ""] {
            fixtures.assertRejected { try self.insertManifest($0, chip: chip, outcome: nil) }
        }
    }

    /// 未知のATMA判定文字列は拒否されます。
    ///
    /// 責務: 未定義値と、大文字小文字だけ異なる値・空文字が保存できないことを確認します。
    func testCheckRejectsUnknownProbeOutcomeString() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }

        for outcome in ["timeout", "Silent", ""] {
            fixtures.assertRejected { try self.insertManifest($0, chip: "stn", outcome: outcome) }
        }
    }

    /// チップ種別なしでATMA判定結果だけを持つ行は拒否されます。
    ///
    /// 責務: 判定結果の単独保存が制約で拒否されることを確認します。
    func testCheckRejectsProbeOutcomeWithoutChipFamily() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }

        fixtures.assertRejected { try self.insertManifest($0, chip: nil, outcome: "framesReceived") }
    }

    // MARK: - immutability trigger

    /// 未封印のmanifest行もチップ種別とATMA判定結果をUPDATEで書き換えられません。
    ///
    /// 責務: 封印遷移を伴わない2列の変更が不変性triggerで拒否され、保存値が残ることを確認します。
    func testUnsealedManifestRejectsAdapterProbeColumnUpdates() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { database in
            try fixtures.insertSession(database)
            try insertManifest(database, chip: "elm327Genuine", outcome: "silent")
        }

        fixtures.assertRejected {
            try self.update($0, "UPDATE connection_session_acquisition_manifests SET adapterChipFamily = 'stn' WHERE sessionID = ?")
        }
        fixtures.assertRejected {
            try self.update($0, "UPDATE connection_session_acquisition_manifests SET adapterMonitorProbeOutcome = 'busError' WHERE sessionID = ?")
        }

        let row = try storedRow(fixtures.queue)
        XCTAssertEqual(row["adapterChipFamily"] as String?, "elm327Genuine")
        XCTAssertEqual(row["adapterMonitorProbeOutcome"] as String?, "silent")
    }

    /// 封印遷移と同時にチップ種別またはATMA判定結果を変えるUPDATEは拒否され、未封印のまま残ります。
    ///
    /// 責務: 正当な封印UPDATEに紛れ込ませた2列の変更をtriggerが比較対象として拒否することを確認します。
    func testSealTransitionThatAlsoChangesAdapterProbeColumnsIsRejected() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { database in
            try fixtures.insertSession(database)
            try insertManifest(database, chip: "elm327Clone", outcome: nil)
            try database.execute(
                sql: """
                    INSERT INTO connection_session_acquisition_raw_boundaries
                    (sessionID, eventKind, occurredAtMicroseconds, endReason) VALUES (?, 'started', 100000000, NULL)
                    """,
                arguments: [SegmentationSchemaFixtures.sessionA]
            )
        }

        fixtures.assertRejected {
            try self.update($0, "UPDATE connection_session_acquisition_manifests SET isSealed = 1, adapterChipFamily = 'stn' WHERE sessionID = ?")
        }
        fixtures.assertRejected {
            try self.update(
                $0,
                "UPDATE connection_session_acquisition_manifests SET isSealed = 1, adapterMonitorProbeOutcome = 'stopped' WHERE sessionID = ?"
            )
        }

        let row = try storedRow(fixtures.queue)
        XCTAssertEqual(row["isSealed"] as Int, 0)
        XCTAssertEqual(row["adapterChipFamily"] as String?, "elm327Clone")
        XCTAssertEqual(row["adapterMonitorProbeOutcome"] as DatabaseValue, .null)
    }

    /// 2列を変えない正当な封印遷移は、判定結果がNULLの行でも従来どおり通ります。
    ///
    /// 責務: trigger の2列比較がNULL同士を不一致扱いして封印を妨げないことを確認します。
    func testValidSealTransitionSucceedsWithAndWithoutProbeOutcome() throws {
        for outcome in [nil, "framesReceived"] as [String?] {
            let fixtures = try SegmentationSchemaFixtures()
            try fixtures.queue.write { database in
                try fixtures.insertSession(database)
                try insertManifest(database, chip: "unknown", outcome: outcome)
                try startAndSeal(database)
            }

            let row = try storedRow(fixtures.queue)
            XCTAssertEqual(row["isSealed"] as Int, 1, "outcome: \(String(describing: outcome))")
            XCTAssertEqual(row["adapterChipFamily"] as String?, "unknown")
            XCTAssertEqual(row["adapterMonitorProbeOutcome"] as String?, outcome)
        }
    }
}
