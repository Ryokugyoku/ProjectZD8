import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// GRDB取得証拠repositoryのcanonical往復、冪等性、rollback、不変性を検証します。
@MainActor
final class GRDBConnectionSessionAcquisitionRepositoryTests: XCTestCase {
    /// 全manifest field、能力状態、選択値、範囲、要求順を往復します。
    ///
    /// 責務: 正規化4表のreadbackがPID配列順を除外し全semantic値を保持することを確認します。
    func testRoundTripPreservesCompleteCanonicalManifestAndOrderedPIDs() throws {
        let fixture = try makeFixture()
        let manifest = try makeManifest(definitionsReversed: true)

        try fixture.repository.saveStartOnce(
            manifest: manifest,
            startedAt: Date(timeIntervalSince1970: 100.123_456_4),
            for: fixture.session.id
        )

        let stored = try fixture.repository.manifest(for: fixture.session.id)
        XCTAssertEqual(stored.manifestVersion, 11)
        XCTAssertEqual(stored.applicationVersion?.marketingVersion, "fixture-marketing")
        XCTAssertEqual(stored.applicationVersion?.buildVersion, "fixture-build")
        XCTAssertEqual(stored.schemaContractVersion, 31)
        XCTAssertEqual(stored.pollingPolicyVersion, 21)
        XCTAssertEqual(stored.acquisitionPlatform, .iPad)
        XCTAssertEqual(stored.modelInputManifestVersion, 41)
        XCTAssertEqual(stored.orderedRequestedPIDs?.requests, [secondRequest, firstRequest])
        XCTAssertEqual(stored.pidDefinitions.map(\.request), [secondRequest, firstRequest])
        XCTAssertEqual(stored.pidDefinitions[0].capabilitySupport, .indeterminate)
        XCTAssertEqual(stored.pidDefinitions[0].isCollectionEnabled, true)
        XCTAssertEqual(stored.pidDefinitions[0].validityRange?.minimum, -40)
        XCTAssertEqual(stored.pidDefinitions[0].validityRange?.maximum, 215)
        XCTAssertEqual(stored.pidDefinitions[1].capabilitySupport, .supported)
        XCTAssertEqual(stored.pidDefinitions[1].isCollectionEnabled, false)
        XCTAssertEqual(stored.pidDefinitions[1].validityRange, .notDeclared)
        guard case let .started(at) = try XCTUnwrap(fixture.repository.boundaryEvidence(for: fixture.session.id).first) else {
            return XCTFail("開始境界ではありません")
        }
        XCTAssertEqual(at.timeIntervalSince1970, 100.123_456, accuracy: 0.000_000_1)
    }

    /// PID definition配列順だけが異なるretryをduplicateとして扱います。
    ///
    /// 責務: PID snapshotの格納順をsemantic identityから除外したcanonical duplicate判定を確認します。
    func testExactRetryIgnoresDefinitionArrayOrderAndDoesNotTrustCallerDigest() throws {
        let fixture = try makeFixture(manifestDigest: "caller-digest-a")
        let startedAt = Date(timeIntervalSince1970: 100.000_000_49)
        try fixture.repository.saveStartOnce(
            manifest: makeManifest(definitionsReversed: false),
            startedAt: startedAt,
            for: fixture.session.id
        )

        XCTAssertThrowsError(
            try fixture.repository.saveStartOnce(
                manifest: makeManifest(definitionsReversed: true),
                startedAt: Date(timeIntervalSince1970: 100.000_000_4),
                for: fixture.session.id
            )
        ) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .duplicate)
        }
    }

    /// manifest、PID集合、要求順、開始時刻のsemantic差をconflictとして扱います。
    ///
    /// 責務: canonical readbackに対する主要semantic差が既存aggregateを更新せず競合になることを確認します。
    func testSemanticDifferencesAreConflicts() throws {
        let fixture = try makeFixture()
        let original = try makeManifest(definitionsReversed: false)
        let startedAt = Date(timeIntervalSince1970: 100)
        try fixture.repository.saveStartOnce(manifest: original, startedAt: startedAt, for: fixture.session.id)

        let conflicts = try [
            makeManifest(manifestVersion: 12),
            makeManifest(marketingVersion: "different"),
            makeManifest(buildVersion: "different"),
            makeManifest(schemaContractVersion: 32),
            makeManifest(pollingPolicyVersion: 22),
            makeManifest(acquisitionPlatform: .macOS),
            makeManifest(modelInputManifestVersion: 42),
            makeManifest(secondSupport: .unsupported),
            makeManifest(secondEnabled: false),
            makeManifest(secondRevision: 9),
            makeManifest(secondRequiredByteCount: 2),
            makeManifest(secondCanonicalizationVersion: 53),
            makeManifest(secondFormula: "A + 1"),
            makeManifest(secondUnit: "kelvin"),
            makeManifest(secondMinimum: -39),
            makeManifest(includeThirdDefinition: true),
            makeManifest(includeSecondDefinition: false, orderedRequests: [firstRequest]),
            makeManifest(orderedRequests: [firstRequest, secondRequest])
        ]
        for manifest in conflicts {
            XCTAssertThrowsError(
                try fixture.repository.saveStartOnce(manifest: manifest, startedAt: startedAt, for: fixture.session.id)
            ) {
                XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .conflict)
            }
        }
        XCTAssertThrowsError(
            try fixture.repository.saveStartOnce(
                manifest: original,
                startedAt: Date(timeIntervalSince1970: 100.000_002),
                for: fixture.session.id
            )
        ) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .conflict)
        }
        XCTAssertEqual(
            try fixture.repository.manifest(for: fixture.session.id),
            try makeManifest(definitionsReversed: true)
        )
    }

    /// 終了境界の欠落、時系列、duplicate、conflictを区別します。
    ///
    /// 責務: appendEndが既存ended判定を優先し新規時だけ開始時刻との前後関係を検証することを確認します。
    func testAppendEndDistinguishesAllDomainOutcomes() throws {
        let missing = try makeFixture()
        XCTAssertThrowsError(
            try missing.repository.appendEnd(at: Date(timeIntervalSince1970: 200), reason: .connectionLost, for: missing.session.id)
        ) { XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .startEvidenceMissing) }

        let fixture = try makeFixture()
        let manifest = try makeManifest()
        try fixture.repository.saveStartOnce(
            manifest: manifest,
            startedAt: Date(timeIntervalSince1970: 100.123_456_4),
            for: fixture.session.id
        )
        XCTAssertThrowsError(
            try fixture.repository.appendEnd(
                at: Date(timeIntervalSince1970: 100.123_455_4),
                reason: .connectionLost,
                for: fixture.session.id
            )
        ) { XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .endBeforeStart) }

        let endedAt = Date(timeIntervalSince1970: 200.654_321_4)
        try fixture.repository.appendEnd(at: endedAt, reason: .userDisconnected, for: fixture.session.id)
        XCTAssertThrowsError(
            try fixture.repository.appendEnd(
                at: Date(timeIntervalSince1970: 200.654_321_49),
                reason: .userDisconnected,
                for: fixture.session.id
            )
        ) { XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .duplicate) }
        XCTAssertThrowsError(
            try fixture.repository.appendEnd(
                at: Date(timeIntervalSince1970: 50),
                reason: .connectionLost,
                for: fixture.session.id
            )
        ) { XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .conflict) }
        XCTAssertEqual(
            try fixture.repository.manifest(for: fixture.session.id),
            try makeManifest(definitionsReversed: true)
        )
        XCTAssertEqual(try fixture.repository.boundaryEvidence(for: fixture.session.id).count, 2)
    }

    /// 各挿入段階、seal、readback失敗で全開始aggregateをrollbackします。
    ///
    /// 責務: transaction内の任意段階失敗が4表に部分状態をcommitしないことを確認します。
    func testEveryStartPersistenceStageFailureRollsBack() throws {
        let failurePoints: [(String, String)] = [
            ("manifest", "BEFORE INSERT ON connection_session_acquisition_manifests"),
            ("definition", "BEFORE INSERT ON connection_session_acquisition_pid_definitions"),
            ("ordered", "BEFORE INSERT ON connection_session_acquisition_ordered_pids"),
            ("started", "BEFORE INSERT ON connection_session_acquisition_raw_boundaries WHEN NEW.eventKind = 'started'"),
            ("seal", "BEFORE UPDATE ON connection_session_acquisition_manifests WHEN NEW.isSealed = 1"),
            ("readback", "AFTER UPDATE ON connection_session_acquisition_manifests WHEN NEW.isSealed = 1")
        ]
        for (name, timing) in failurePoints {
            let fixture = try makeFixture()
            try fixture.queue.write { database in
                let body = name == "readback"
                    ? "DELETE FROM connection_session_acquisition_manifests WHERE sessionID = NEW.sessionID;"
                    : "SELECT RAISE(ABORT, 'injected failure');"
                try database.execute(sql: "CREATE TRIGGER injected_\(name) \(timing) BEGIN \(body) END;")
            }
            XCTAssertThrowsError(
                try fixture.repository.saveStartOnce(
                    manifest: makeManifest(),
                    startedAt: Date(timeIntervalSince1970: 100),
                    for: fixture.session.id
                )
            ) { XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .unavailable) }
            try assertAcquisitionTablesAreEmpty(fixture.queue)
        }
    }

    /// DB直接変更、seal後追加、重複event、ordinal gapをconstraintとtriggerで拒否します。
    ///
    /// 責務: repositoryを迂回したsemantic mutationと不正追加をSQLite schemaが拒否することを確認します。
    func testDatabaseConstraintsRejectMutationAndInvalidAppend() throws {
        let fixture = try makeFixture()
        try fixture.repository.saveStartOnce(
            manifest: makeManifest(),
            startedAt: Date(timeIntervalSince1970: 100),
            for: fixture.session.id
        )
        let key = fixture.session.id.rawValue.uuidString.lowercased()
        try fixture.queue.write { database in
            XCTAssertThrowsError(try database.execute(
                sql: "UPDATE connection_session_acquisition_manifests SET pollingPolicyVersion = 99 WHERE sessionID = ?",
                arguments: [key]
            ))
            XCTAssertThrowsError(try database.execute(
                sql: "UPDATE connection_session_acquisition_pid_definitions SET unit = 'x' WHERE sessionID = ?",
                arguments: [key]
            ))
            XCTAssertThrowsError(try database.execute(
                sql: "UPDATE connection_session_acquisition_ordered_pids SET ordinal = 5 WHERE sessionID = ? AND ordinal = 0",
                arguments: [key]
            ))
            XCTAssertThrowsError(try database.execute(
                sql: "UPDATE connection_session_acquisition_raw_boundaries SET occurredAtMicroseconds = 1 WHERE sessionID = ?",
                arguments: [key]
            ))
            XCTAssertThrowsError(try database.execute(
                sql: """
                INSERT INTO connection_session_acquisition_pid_definitions
                    (sessionID, service, pid, capabilitySupport, isCollectionEnabled,
                     definitionRevision, requiredByteCount, formulaCanonicalizationVersion,
                     formulaExpression, unit, validityRangeKind, minimumValue, maximumValue)
                VALUES (?, 1, 13, 'supported', 1, 1, 1, 1, 'A', 'raw', 'notDeclared', NULL, NULL)
                """,
                arguments: [key]
            ))
            XCTAssertThrowsError(try database.execute(
                sql: "INSERT INTO connection_session_acquisition_ordered_pids VALUES (?, 2, 1, 12)",
                arguments: [key]
            ))
            XCTAssertThrowsError(try database.execute(
                sql: "INSERT INTO connection_session_acquisition_raw_boundaries VALUES (?, 'started', 100000000, NULL)",
                arguments: [key]
            ))
            try database.execute(
                sql: "INSERT INTO connection_session_acquisition_raw_boundaries VALUES (?, 'ended', 200000000, 'userDisconnected')",
                arguments: [key]
            )
            XCTAssertThrowsError(try database.execute(
                sql: "INSERT INTO connection_session_acquisition_raw_boundaries VALUES (?, 'ended', 200000000, 'userDisconnected')",
                arguments: [key]
            ))
        }
    }

    /// 親session削除時に新4表を全てcascade削除します。
    ///
    /// 責務: append-only triggerが既存の親session削除契約を妨げないことを確認します。
    func testParentSessionDeletionCascadesAllAcquisitionTables() throws {
        let fixture = try makeFixture()
        try fixture.repository.saveStartOnce(
            manifest: makeManifest(),
            startedAt: Date(timeIntervalSince1970: 100),
            for: fixture.session.id
        )

        try fixture.sessionRepository.deleteSession(fixture.session.id, for: fixture.session.accountIdentifier)

        try assertAcquisitionTablesAreEmpty(fixture.queue)
    }

    /// ordinal gapと複合key重複をseal前schema操作でも拒否します。
    ///
    /// 責務: 要求順が0...count-1でないaggregateとordinal/PID重複をSQLite制約で確定できないことを確認します。
    func testOrdinalGapAndDuplicatesAreRejectedBeforeSeal() throws {
        let fixture = try makeFixture()
        let key = fixture.session.id.rawValue.uuidString.lowercased()
        try fixture.queue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO connection_session_acquisition_manifests VALUES
                    (?, 1, 'fixture', '1', 1, 1, 'macOS', 1, 0)
                    """,
                arguments: [key]
            )
            try database.execute(
                sql: """
                    INSERT INTO connection_session_acquisition_pid_definitions VALUES
                    (?, 1, 12, 'supported', 1, 1, 2, 1, 'A', 'rpm', 'notDeclared', NULL, NULL)
                    """,
                arguments: [key]
            )
            XCTAssertThrowsError(try database.execute(
                sql: """
                    INSERT INTO connection_session_acquisition_pid_definitions VALUES
                    (?, 1, 13, 'supported', 1, 1, 1, 1, 'A', 'unit', 'inclusive', NULL, NULL)
                    """,
                arguments: [key]
            ))
            XCTAssertThrowsError(try database.execute(
                sql: """
                    INSERT INTO connection_session_acquisition_pid_definitions VALUES
                    (?, 1, 14, 'supported', 1, 1, 1, 1, 'A', 'unit', 'notDeclared', 0, 1)
                    """,
                arguments: [key]
            ))
            try database.execute(
                sql: "INSERT INTO connection_session_acquisition_ordered_pids VALUES (?, 1, 1, 12)",
                arguments: [key]
            )
            try database.execute(
                sql: "INSERT INTO connection_session_acquisition_raw_boundaries VALUES (?, 'started', 100000000, NULL)",
                arguments: [key]
            )
            XCTAssertThrowsError(try database.execute(
                sql: "UPDATE connection_session_acquisition_manifests SET isSealed = 1 WHERE sessionID = ?",
                arguments: [key]
            ))
            XCTAssertThrowsError(try database.execute(
                sql: "INSERT INTO connection_session_acquisition_ordered_pids VALUES (?, 1, 1, 12)",
                arguments: [key]
            ))
            XCTAssertThrowsError(try database.execute(
                sql: "INSERT INTO connection_session_acquisition_ordered_pids VALUES (?, 2, 1, 12)",
                arguments: [key]
            ))
        }
    }

    /// 親session欠落をGRDB errorではなくunavailableへmappingします。
    ///
    /// 責務: 存在しない親sessionへの開始保存が4表を変更せずDomain errorだけを返すことを確認します。
    func testMissingParentMapsToUnavailableWithoutPartialRows() throws {
        let queue = try DatabaseQueue()
        let repository = try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue)
        let missingID = ConnectionSessionID(rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9)))

        XCTAssertThrowsError(
            try repository.saveStartOnce(
                manifest: makeManifest(),
                startedAt: Date(timeIntervalSince1970: 100),
                for: missingID
            )
        ) { XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .unavailable) }
        try assertAcquisitionTablesAreEmpty(queue)
    }

    /// evidenceのないlegacy sessionをnotFoundと空境界として読み取ります。
    ///
    /// 責務: migrationがlegacy sessionへ推測manifestを生成せず欠落を明示的に返すことを確認します。
    func testLegacySessionWithoutEvidenceReadsAsNotFound() throws {
        let fixture = try makeFixture()

        XCTAssertThrowsError(try fixture.repository.manifest(for: fixture.session.id)) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .notFound)
        }
        XCTAssertTrue(try fixture.repository.boundaryEvidence(for: fixture.session.id).isEmpty)
    }

    /// 破損によりendedだけが残った境界列をDomain eventへ復元しません。
    ///
    /// 責務: canonical manifest読取と境界読取が不完全な保存状態を `.unavailable` へ変換することを確認します。
    func testCorruptEndedOnlyBoundaryMapsToUnavailable() throws {
        let fixture = try makeFixture()
        try fixture.repository.saveStartOnce(
            manifest: makeManifest(),
            startedAt: Date(timeIntervalSince1970: 100),
            for: fixture.session.id
        )
        try fixture.repository.appendEnd(
            at: Date(timeIntervalSince1970: 200),
            reason: .userDisconnected,
            for: fixture.session.id
        )
        let key = fixture.session.id.rawValue.uuidString.lowercased()
        try fixture.queue.write { database in
            try database.execute(
                sql: "DELETE FROM connection_session_acquisition_raw_boundaries WHERE sessionID = ? AND eventKind = 'started'",
                arguments: [key]
            )
        }

        XCTAssertThrowsError(try fixture.repository.manifest(for: fixture.session.id)) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .unavailable)
        }
        XCTAssertThrowsError(try fixture.repository.boundaryEvidence(for: fixture.session.id)) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .unavailable)
        }
    }

    /// microsecondへcanonical化できないDateをunavailableとして拒否します。
    ///
    /// 責務: 非有限時刻がSQLite integer変換をtrapまたは部分保存へ進めないことを確認します。
    func testUnrepresentableTimestampMapsToUnavailable() throws {
        let fixture = try makeFixture()

        XCTAssertThrowsError(
            try fixture.repository.saveStartOnce(
                manifest: makeManifest(),
                startedAt: Date(timeIntervalSince1970: .infinity),
                for: fixture.session.id
            )
        ) { XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .unavailable) }
        try assertAcquisitionTablesAreEmpty(fixture.queue)
    }

    /// 同時exact retryが1成功と1duplicateに直列化されます。
    ///
    /// 責務: 競合する2書込が部分aggregateを作らず同じcanonical結果へ収束することを確認します。
    func testConcurrentExactRetryDoesNotCreatePartialState() async throws {
        let fixture = try makeFixture()
        let manifest = try makeManifest()
        let startedAt = Date(timeIntervalSince1970: 100)
        let outcomes = await withTaskGroup(
            of: ConnectionSessionAcquisitionRepositoryError?.self,
            returning: [ConnectionSessionAcquisitionRepositoryError?].self
        ) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        try fixture.repository.saveStartOnce(
                            manifest: manifest,
                            startedAt: startedAt,
                            for: fixture.session.id
                        )
                        return nil
                    } catch let error as ConnectionSessionAcquisitionRepositoryError {
                        return error
                    } catch {
                        return .unavailable
                    }
                }
            }
            var values: [ConnectionSessionAcquisitionRepositoryError?] = []
            for await value in group { values.append(value) }
            return values
        }

        XCTAssertEqual(outcomes.compactMap { $0 }, [.duplicate])
        XCTAssertEqual(try fixture.repository.boundaryEvidence(for: fixture.session.id).count, 1)
        try await fixture.queue.read { database in
            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM connection_session_acquisition_manifests"), 1)
            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM connection_session_acquisition_raw_boundaries"), 1)
        }
    }

    /// repositoryと親sessionを共有するtest fixtureを生成します。
    ///
    /// 責務: migration済み一時DBへsynthetic親sessionを1件保存してintegration test境界を返します。
    /// - Parameter manifestDigest: semantic判定に使用してはならない既存session側digest。
    /// - Returns: Queue、両repository、親sessionの組。
    /// - Throws: DB生成または親session保存失敗。
    private func makeFixture(manifestDigest: String? = nil) throws -> RepositoryFixture {
        let queue = try DatabaseQueue()
        let sessionRepository = try GRDBConnectionSessionRepository(databaseQueue: queue)
        let repository = try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue)
        var session = ConnectionSession(
            id: ConnectionSessionID(rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))),
            accountIdentifier: "fixture-account",
            startedAt: Date(timeIntervalSince1970: 90)
        )
        session.rawLogSummary.manifestDigest = manifestDigest
        try sessionRepository.save(session)
        return RepositoryFixture(
            queue: queue,
            sessionRepository: sessionRepository,
            repository: repository,
            session: session
        )
    }

    /// semantic差を選択できる完全manifestを生成します。
    ///
    /// 責務: integration testへ識別情報を含まない決定的取得manifestを提供します。
    /// - Parameters:
    ///   - manifestVersion: manifest構造version。
    ///   - marketingVersion: app marketing semantic値。
    ///   - buildVersion: app build semantic値。
    ///   - schemaContractVersion: 保存schema semantic値。
    ///   - pollingPolicyVersion: polling方針semantic値。
    ///   - acquisitionPlatform: 取得platform semantic値。
    ///   - modelInputManifestVersion: model入力semantic値。
    ///   - secondSupport: 第2 PIDの能力状態。
    ///   - secondEnabled: 第2 PIDの収集選択。
    ///   - secondRevision: 第2 PIDの定義revision。
    ///   - secondRequiredByteCount: 第2 PIDの必要byte数。
    ///   - secondCanonicalizationVersion: 第2 PIDの式canonicalization version。
    ///   - secondFormula: 第2 PIDの式semantic値。
    ///   - secondUnit: 第2 PIDの単位。
    ///   - secondMinimum: 第2 PIDの有効範囲下限。
    ///   - includeThirdDefinition: 要求外の第3 PID definitionを追加するかどうか。
    ///   - includeSecondDefinition: 第2 PID definitionを含めるかどうか。
    ///   - orderedRequests: semantic要求順。
    ///   - definitionsReversed: 入力配列だけを逆順にするかどうか。
    /// - Returns: 保存可能な完全manifest。
    /// - Throws: Domain値生成失敗。
    private func makeManifest(
        manifestVersion: Int = 11,
        marketingVersion: String = "fixture-marketing",
        buildVersion: String = "fixture-build",
        schemaContractVersion: Int = 31,
        pollingPolicyVersion: Int = 21,
        acquisitionPlatform: ConnectionSessionAcquisitionPlatform = .iPad,
        modelInputManifestVersion: Int = 41,
        secondSupport: AcquisitionPIDCapabilitySupport = .indeterminate,
        secondEnabled: Bool = true,
        secondRevision: Int = 8,
        secondRequiredByteCount: Int = 1,
        secondCanonicalizationVersion: Int = 52,
        secondFormula: String = "A - 40",
        secondUnit: String = "celsius",
        secondMinimum: Double = -40,
        includeThirdDefinition: Bool = false,
        includeSecondDefinition: Bool = true,
        orderedRequests: [OBDPIDRequest]? = nil,
        definitionsReversed: Bool = false
    ) throws -> ConnectionSessionAcquisitionManifest {
        let first = try AcquisitionPIDDefinitionSnapshot(
            request: firstRequest,
            capabilitySupport: .supported,
            isCollectionEnabled: false,
            definitionRevision: 7,
            requiredByteCount: 2,
            definitionIdentity: AcquisitionPIDDefinitionIdentity(canonicalizationVersion: 51, expression: "(A * 256 + B) / 4"),
            unit: "rpm",
            validityRange: .notDeclared
        )
        let second = try AcquisitionPIDDefinitionSnapshot(
            request: secondRequest,
            capabilitySupport: secondSupport,
            isCollectionEnabled: secondEnabled,
            definitionRevision: secondRevision,
            requiredByteCount: secondRequiredByteCount,
            definitionIdentity: AcquisitionPIDDefinitionIdentity(
                canonicalizationVersion: secondCanonicalizationVersion,
                expression: secondFormula
            ),
            unit: secondUnit,
            validityRange: .inclusive(minimum: secondMinimum, maximum: 215)
        )
        var definitions = includeSecondDefinition ? [first, second] : [first]
        if includeThirdDefinition {
            definitions.append(try AcquisitionPIDDefinitionSnapshot(
                request: thirdRequest,
                capabilitySupport: .unsupported,
                isCollectionEnabled: false,
                definitionRevision: 1,
                requiredByteCount: 1,
                definitionIdentity: AcquisitionPIDDefinitionIdentity(canonicalizationVersion: 1, expression: "A"),
                unit: "percent",
                validityRange: .notDeclared
            ))
        }
        if definitionsReversed { definitions.reverse() }
        return try ConnectionSessionAcquisitionManifest(
            manifestVersion: manifestVersion,
            applicationVersion: AcquisitionApplicationVersion(
                marketingVersion: marketingVersion,
                buildVersion: buildVersion
            ),
            schemaContractVersion: schemaContractVersion,
            pollingPolicyVersion: pollingPolicyVersion,
            orderedRequestedPIDs: OrderedAcquisitionPIDSet(
                requests: orderedRequests ?? [secondRequest, firstRequest]
            ),
            pidDefinitions: definitions,
            acquisitionPlatform: acquisitionPlatform,
            modelInputManifestVersion: modelInputManifestVersion
        )
    }

    /// 新4表が全て空であることを確認します。
    ///
    /// 責務: rollbackまたはcascade後に取得証拠の部分行が残らないことを検証します。
    /// - Parameter queue: 検証対象DB Queue。
    /// - Throws: SQLite読取失敗。
    private func assertAcquisitionTablesAreEmpty(_ queue: DatabaseQueue) throws {
        try queue.read { database in
            for table in [
                "connection_session_acquisition_manifests",
                "connection_session_acquisition_pid_definitions",
                "connection_session_acquisition_ordered_pids",
                "connection_session_acquisition_raw_boundaries"
            ] {
                XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table)"), 0)
            }
        }
    }

    /// engine speedのsynthetic要求です。
    private var firstRequest: OBDPIDRequest { OBDPIDRequest(service: 1, pid: 12) }
    /// coolant temperatureのsynthetic要求です。
    private var secondRequest: OBDPIDRequest { OBDPIDRequest(service: 1, pid: 5) }
    /// throttle positionのsynthetic要求です。
    private var thirdRequest: OBDPIDRequest { OBDPIDRequest(service: 1, pid: 17) }
}

/// repository integration testで共有するDBと親sessionです。
private struct RepositoryFixture {
    /// 一時SQLite Queueです。
    let queue: DatabaseQueue
    /// 親sessionの保存と削除を行う既存repositoryです。
    let sessionRepository: GRDBConnectionSessionRepository
    /// 検証対象の取得証拠repositoryです。
    let repository: GRDBConnectionSessionAcquisitionRepository
    /// 新4表の親となるsynthetic sessionです。
    let session: ConnectionSession
}
