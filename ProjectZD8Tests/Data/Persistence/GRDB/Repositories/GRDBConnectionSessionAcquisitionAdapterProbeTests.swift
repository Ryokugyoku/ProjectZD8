import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 取得manifestへ保存するアダプター判定証跡(チップ種別とATMA判定結果)の往復と保存文字列を検証します。
@MainActor
final class GRDBConnectionSessionAcquisitionAdapterProbeTests: XCTestCase {
    /// 全チップ種別と、仕様が定める保存文字列の組です。
    private static let chipFamilies: [(OBDAdapterChipFamily, String)] = [
        (.stn, "stn"),
        (.elm327Genuine, "elm327Genuine"),
        (.elm327Clone, "elm327Clone"),
        (.unknown, "unknown")
    ]
    /// 全ATMA判定結果と、仕様が定める保存文字列の組です。
    private static let probeOutcomes: [(OBDMonitorProbeOutcome, String)] = [
        (.framesReceived, "framesReceived"),
        (.unsupported, "unsupported"),
        (.bufferFull, "bufferFull"),
        (.silent, "silent"),
        (.busError, "busError"),
        (.stopped, "stopped")
    ]

    /// 同じDBを共有するRepositoryの組です。
    private struct Fixture {
        /// 一時SQLite Queueです。
        let queue: DatabaseQueue
        /// 親セッションを保存するRepositoryです。
        let sessions: GRDBConnectionSessionRepository
        /// 検証対象の取得証跡Repositoryです。
        let acquisition: GRDBConnectionSessionAcquisitionRepository
    }

    /// 空のインメモリDBへ両Repositoryを生成します。
    ///
    /// 責務: 1件のテスト専用DBと、同じQueueを共有するセッション・取得証跡Repositoryを返します。
    /// - Returns: 生成したFixture。
    /// - Throws: DB作成またはMigrationの失敗。
    private func makeFixture() throws -> Fixture {
        let queue = try DatabaseQueue()
        return Fixture(
            queue: queue,
            sessions: try GRDBConnectionSessionRepository(databaseQueue: queue),
            acquisition: try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue)
        )
    }

    /// 指定したアダプター判定証跡を持つ完全manifestを生成します。
    ///
    /// 責務: 1件のPID定義と要求順を持ち、保存可能な決定的manifestを返します。
    /// - Parameter evidence: manifestへ含めるアダプター判定証跡。
    /// - Returns: 保存可能な完全manifest。
    /// - Throws: Domain値生成失敗。
    private func makeManifest(evidence: AcquisitionAdapterProbeEvidence?) throws -> ConnectionSessionAcquisitionManifest {
        let request = OBDPIDRequest(service: 1, pid: 12)
        let definition = try AcquisitionPIDDefinitionSnapshot(
            request: request,
            capabilitySupport: .supported,
            isCollectionEnabled: true,
            definitionRevision: 1,
            requiredByteCount: 2,
            definitionIdentity: AcquisitionPIDDefinitionIdentity(canonicalizationVersion: 1, expression: "(A * 256 + B) / 4"),
            unit: "rpm",
            validityRange: .notDeclared
        )
        return try ConnectionSessionAcquisitionManifest(
            manifestVersion: 1,
            applicationVersion: AcquisitionApplicationVersion(marketingVersion: "fixture", buildVersion: "1"),
            schemaContractVersion: 1,
            pollingPolicyVersion: 1,
            orderedRequestedPIDs: OrderedAcquisitionPIDSet(requests: [request]),
            pidDefinitions: [definition],
            acquisitionPlatform: .iPhone,
            modelInputManifestVersion: 1,
            adapterProbeEvidence: evidence
        )
    }

    /// 親セッションを保存し、指定証跡を持つmanifestの開始証拠を保存します。
    ///
    /// 責務: 実Repository経由で1件のセッションと封印済みmanifestを作ります。
    /// - Parameters:
    ///   - fixture: 保存先。
    ///   - evidence: manifestへ含めるアダプター判定証跡。
    /// - Returns: 保存したセッションID。
    /// - Throws: 保存の失敗。
    private func saveStart(_ fixture: Fixture, evidence: AcquisitionAdapterProbeEvidence?) throws -> ConnectionSessionID {
        let session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 90))
        try fixture.sessions.save(session)
        try fixture.acquisition.saveStartOnce(
            manifest: makeManifest(evidence: evidence),
            startedAt: Date(timeIntervalSince1970: 100),
            for: session.id
        )
        return session.id
    }

    /// 保存済みmanifest行のアダプター判定2列を直接読みます。
    ///
    /// 責務: Repositoryの復元を経由せず、保存文字列をそのまま返します。
    /// - Parameters:
    ///   - fixture: 読取元。
    ///   - id: 対象セッションID。
    /// - Returns: チップ種別列とATMA判定列の保存値。
    /// - Throws: SQLite読込失敗、または行が無い場合の `XCTUnwrap` 失敗。
    private func storedColumns(_ fixture: Fixture, _ id: ConnectionSessionID) throws -> (chip: String?, outcome: String?) {
        let row = try fixture.queue.read { database in
            try Row.fetchOne(
                database,
                sql: """
                    SELECT adapterChipFamily, adapterMonitorProbeOutcome
                    FROM connection_session_acquisition_manifests WHERE sessionID = ?
                    """,
                arguments: [id.rawValue.uuidString.lowercased()]
            )
        }
        let unwrapped = try XCTUnwrap(row)
        return (unwrapped["adapterChipFamily"], unwrapped["adapterMonitorProbeOutcome"])
    }

    // MARK: - round trip

    /// 全チップ種別と全ATMA判定結果の組は保存後に同じ証跡で読み戻せます。
    ///
    /// 責務: 4種のチップ種別×6種の判定結果の全組み合わせが往復で失われないことを確認します。
    func testEveryChipFamilyAndProbeOutcomeRoundTrips() throws {
        let fixture = try makeFixture()
        for (chip, _) in Self.chipFamilies {
            for (outcome, _) in Self.probeOutcomes {
                let evidence = AcquisitionAdapterProbeEvidence(chipFamily: chip, monitorProbeOutcome: outcome)
                let id = try saveStart(fixture, evidence: evidence)

                XCTAssertEqual(try fixture.acquisition.manifest(for: id).adapterProbeEvidence, evidence, "\(chip) / \(outcome)")
            }
        }
    }

    /// ATMA未試行(判定結果 `nil`)の証跡は全チップ種別で `nil` のまま読み戻せます。
    ///
    /// 責務: 判定結果の欠落がチップ種別ごと消えたり別の値へ化けたりしないことを確認します。
    func testEveryChipFamilyWithoutProbeOutcomeRoundTrips() throws {
        let fixture = try makeFixture()
        for (chip, _) in Self.chipFamilies {
            let evidence = AcquisitionAdapterProbeEvidence(chipFamily: chip, monitorProbeOutcome: nil)
            let id = try saveStart(fixture, evidence: evidence)

            let loaded = try XCTUnwrap(try fixture.acquisition.manifest(for: id).adapterProbeEvidence, "\(chip)")
            XCTAssertEqual(loaded.chipFamily, chip)
            XCTAssertNil(loaded.monitorProbeOutcome, "\(chip)")
        }
    }

    /// 証跡なしのmanifestは保存後も証跡 `nil` で、2列ともNULLです。
    ///
    /// 責務: 証跡欠落が既定のチップ種別などへ補完されないことを確認します。
    func testManifestWithoutEvidenceRoundTripsAsNil() throws {
        let fixture = try makeFixture()
        let id = try saveStart(fixture, evidence: nil)

        XCTAssertNil(try fixture.acquisition.manifest(for: id).adapterProbeEvidence)
        let stored = try storedColumns(fixture, id)
        XCTAssertNil(stored.chip)
        XCTAssertNil(stored.outcome)
    }

    // MARK: - stored strings

    /// チップ種別は仕様の安定文字列で保存されます。
    ///
    /// 責務: 各チップ種別の保存列値が `stn` / `elm327Genuine` / `elm327Clone` / `unknown` であることを確認します。
    func testChipFamilyIsStoredAsStableString() throws {
        let fixture = try makeFixture()
        for (chip, expected) in Self.chipFamilies {
            let id = try saveStart(fixture, evidence: AcquisitionAdapterProbeEvidence(chipFamily: chip, monitorProbeOutcome: nil))

            XCTAssertEqual(try storedColumns(fixture, id).chip, expected)
        }
    }

    /// ATMA判定結果は仕様の安定文字列で保存されます。
    ///
    /// 責務: 各判定結果の保存列値が仕様の6種の文字列であることを確認します。
    func testProbeOutcomeIsStoredAsStableString() throws {
        let fixture = try makeFixture()
        for (outcome, expected) in Self.probeOutcomes {
            let id = try saveStart(fixture, evidence: AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: outcome))

            XCTAssertEqual(try storedColumns(fixture, id).outcome, expected)
        }
    }

    // MARK: - immutability after save

    /// 保存(封印)後のmanifest行はチップ種別もATMA判定結果もUPDATEで書き換えられません。
    ///
    /// 責務: 封印済み行の2列の変更とNULL化が不変性triggerで拒否され、保存値が残ることを確認します。
    func testSealedManifestRejectsAdapterProbeColumnUpdates() throws {
        let fixture = try makeFixture()
        let evidence = AcquisitionAdapterProbeEvidence(chipFamily: .elm327Clone, monitorProbeOutcome: .bufferFull)
        let id = try saveStart(fixture, evidence: evidence)
        let key = id.rawValue.uuidString.lowercased()
        let updates = [
            "UPDATE connection_session_acquisition_manifests SET adapterChipFamily = 'stn' WHERE sessionID = ?",
            "UPDATE connection_session_acquisition_manifests SET adapterMonitorProbeOutcome = 'silent' WHERE sessionID = ?",
            "UPDATE connection_session_acquisition_manifests SET adapterMonitorProbeOutcome = NULL WHERE sessionID = ?"
        ]
        for sql in updates {
            XCTAssertThrowsError(try fixture.queue.write { try $0.execute(sql: sql, arguments: [key]) }, sql) { error in
                XCTAssertEqual((error as? DatabaseError)?.resultCode, .SQLITE_CONSTRAINT, "\(sql): \(error)")
            }
        }

        XCTAssertEqual(try fixture.acquisition.manifest(for: id).adapterProbeEvidence, evidence)
    }
}
