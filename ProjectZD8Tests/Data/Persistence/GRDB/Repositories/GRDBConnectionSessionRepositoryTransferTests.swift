import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionRepository` のCloudKit概要取込とRaw転送復元を分岐・境界単位で検証します。
@MainActor
final class GRDBConnectionSessionRepositoryTransferTests: XCTestCase {
    /// 転送側セッションの複製へ変更を加えて返します。
    ///
    /// 責務: 保存済みセッションと同じIDを保ったまま、指定項目だけ異なる転送セッションを作ります。
    /// - Parameters:
    ///   - session: 元のセッション。
    ///   - mutate: 複製へ適用する変更。
    /// - Returns: 変更済みの複製。
    private func transferred(_ session: ConnectionSession, _ mutate: (inout ConnectionSession) -> Void) -> ConnectionSession {
        var copy = session
        mutate(&copy)
        return copy
    }

    /// 全メタデータを持つ終了済みセッションを保存します。
    ///
    /// 責務: 互換性判定の全項目に値を持つ1件のセッションをRepositoryへ保存します。
    /// - Parameter fixtures: 保存先。
    /// - Returns: 保存したセッション。
    /// - Throws: 保存の失敗。
    private func saveFullSession(_ fixtures: GRDBConnectionSessionRepositoryFixtures) throws -> ConnectionSession {
        var session = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 1_000),
            vehicle: ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "ZD8"),
            acquisitionDevice: ConnectionSessionAcquisitionDevice(platform: .iPhone, name: "iPhone")
        )
        session.endedAt = Date(timeIntervalSince1970: 1_010)
        session.endReason = .userDisconnected
        session.startingOdometerKilometers = 100
        session.endingOdometerKilometers = 110
        session.distanceSourceModelCode = "ZD8"
        try fixtures.repository.save(session)
        return session
    }

    // MARK: - importCloudMetadata guards

    /// 未終了セッション・空アカウント・空Digestの概要は `integrityConflict` で保存されません。
    ///
    /// 責務: 取込前提(終了済み、アカウント、Digest)を満たさない概要を拒否することを確認します。
    func testImportCloudMetadataRejectsOpenSessionEmptyAccountAndEmptyDigest() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let open = ConnectionSession(accountIdentifier: "account")
        let noAccount = GRDBConnectionSessionRepositoryFixtures.endedSession(account: "")
        let valid = GRDBConnectionSessionRepositoryFixtures.endedSession()

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.importCloudMetadata(ConnectionSessionCloudMetadata(session: open, manifestDigest: "d"))
        }
        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.importCloudMetadata(ConnectionSessionCloudMetadata(session: noAccount, manifestDigest: "d"))
        }
        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.importCloudMetadata(ConnectionSessionCloudMetadata(session: valid, manifestDigest: ""))
        }
        let count = try fixtures.queue.read { try ConnectionSessionRecord.fetchCount($0) }
        XCTAssertEqual(count, 0)
    }

    // MARK: - importCloudMetadata new session

    /// 未保存セッションはRaw件数0なら `empty`、1件以上なら `removed` で `uploaded` として挿入されます。
    ///
    /// 責務: 新規挿入時の端末固有状態(受領証・閲覧日時なし)と件数引継ぎを確認します。
    func testImportCloudMetadataInsertsNewSessionWithStateDerivedFromRecordCount() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        var withRaw = GRDBConnectionSessionRepositoryFixtures.endedSession(startedAt: Date(timeIntervalSince1970: 100))
        withRaw.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 4,
            byteCount: 40,
            localState: .available,
            cloudState: .failed,
            manifestDigest: "ignored",
            macImportReceipt: ConnectionSessionMacImportReceipt(
                deviceID: "mac", deviceName: "Mac", importedAt: Date(timeIntervalSince1970: 1), manifestDigest: "ignored"
            ),
            lastAccessedAt: Date(timeIntervalSince1970: 2)
        )
        let withoutRaw = GRDBConnectionSessionRepositoryFixtures.endedSession(startedAt: Date(timeIntervalSince1970: 200))

        try fixtures.repository.importCloudMetadata(ConnectionSessionCloudMetadata(session: withRaw, manifestDigest: "digest-a"))
        try fixtures.repository.importCloudMetadata(ConnectionSessionCloudMetadata(session: withoutRaw, manifestDigest: "digest-b"))

        let rawRecord = try fixtures.storedRecord(withRaw.id)
        XCTAssertEqual(rawRecord.localRawState, "removed")
        XCTAssertEqual(rawRecord.cloudSyncState, "uploaded")
        XCTAssertEqual(rawRecord.manifestDigest, "digest-a")
        XCTAssertEqual(rawRecord.rawRecordCount, 4)
        XCTAssertEqual(rawRecord.rawByteCount, 40)
        XCTAssertNil(rawRecord.macImportedManifestDigest)
        XCTAssertNil(rawRecord.rawLastAccessedAt)
        let emptyRecord = try fixtures.storedRecord(withoutRaw.id)
        XCTAssertEqual(emptyRecord.localRawState, "empty")
        XCTAssertEqual(emptyRecord.cloudSyncState, "uploaded")
        XCTAssertEqual(emptyRecord.manifestDigest, "digest-b")
    }

    // MARK: - importCloudMetadata existing session compatibility

    /// 既存セッションと必須項目または両側にある任意項目が矛盾する概要は `integrityConflict` です。
    ///
    /// 責務: アカウント・日時・終了原因・車両・端末・走行距離・型式の各矛盾を拒否し保存済み行を変えないことを確認します。
    func testImportCloudMetadataRejectsEachIncompatibleField() throws {
        let cases: [(String, (inout ConnectionSession) -> Void)] = [
            ("account", { $0 = ConnectionSession(copying: $0, account: "other") }),
            ("startedAt", { $0 = ConnectionSession(copying: $0, startedAt: $0.startedAt.addingTimeInterval(0.002)) }),
            ("endedAt", { $0.endedAt = $0.endedAt?.addingTimeInterval(0.002) }),
            ("endReason", { $0.endReason = .connectionLost }),
            ("vehicle", { $0.vehicle = ConnectionSessionVehicle(id: VehicleID(), name: "X", displayIdentifier: "Y") }),
            ("device", { $0.acquisitionDevice = ConnectionSessionAcquisitionDevice(platform: .macOS, name: "Mac") }),
            ("startingOdometer", { $0.startingOdometerKilometers = 101 }),
            ("endingOdometer", { $0.endingOdometerKilometers = 111 }),
            ("modelCode", { $0.distanceSourceModelCode = "OTHER" })
        ]
        for (name, mutate) in cases {
            let fixtures = try GRDBConnectionSessionRepositoryFixtures()
            let existing = try saveFullSession(fixtures)
            let before = try fixtures.storedRecord(existing.id)
            let incompatible = transferred(existing, mutate)

            assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
                try fixtures.repository.importCloudMetadata(
                    ConnectionSessionCloudMetadata(session: incompatible, manifestDigest: "digest")
                )
            }
            let after = try fixtures.storedRecord(existing.id)
            XCTAssertEqual(after.cloudSyncState, before.cloudSyncState, "case: \(name)")
            XCTAssertEqual(after.manifestDigest, before.manifestDigest, "case: \(name)")
        }
    }

    /// 既存が未終了のセッションへ終了済み概要を取り込むと終了日時の欠落差で `integrityConflict` です。
    ///
    /// 責務: 任意日時の片側だけ欠落している場合を不一致として扱うことを確認します。
    func testImportCloudMetadataRejectsExistingOpenSession() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let open = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        try fixtures.repository.save(open)
        let ended = transferred(open) {
            $0.endedAt = Date(timeIntervalSince1970: 110)
            $0.endReason = .userDisconnected
        }

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.importCloudMetadata(ConnectionSessionCloudMetadata(session: ended, manifestDigest: "d"))
        }
    }

    /// 1ミリ秒以内の日時差と片側欠落の任意項目は互換とみなされ取り込めます。
    ///
    /// 責務: 日時許容差の境界(1ms)と、転送側が欠落した任意項目で既存値を保持することを確認します。
    func testImportCloudMetadataAcceptsMillisecondDifferenceAndMissingOptionalFields() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let existing = try saveFullSession(fixtures)
        let compatible = transferred(existing) {
            $0 = ConnectionSession(copying: $0, startedAt: $0.startedAt.addingTimeInterval(0.001))
            $0.endedAt = $0.endedAt?.addingTimeInterval(0.001)
            $0.vehicle = nil
            $0.acquisitionDevice = nil
            $0.startingOdometerKilometers = nil
            $0.endingOdometerKilometers = nil
            $0.distanceSourceModelCode = nil
        }

        try fixtures.repository.importCloudMetadata(ConnectionSessionCloudMetadata(session: compatible, manifestDigest: "digest"))

        let loaded = try XCTUnwrap(fixtures.repository.sessions(for: "account").first)
        XCTAssertEqual(loaded.vehicle, existing.vehicle)
        XCTAssertEqual(loaded.acquisitionDevice, existing.acquisitionDevice)
        XCTAssertEqual(loaded.startingOdometerKilometers, 100)
        XCTAssertEqual(loaded.endingOdometerKilometers, 110)
        XCTAssertEqual(loaded.distanceSourceModelCode, "ZD8")
        XCTAssertEqual(loaded.startedAt, existing.startedAt)
        XCTAssertEqual(loaded.rawLogSummary.manifestDigest, "digest")
    }

    /// 既存で欠落している任意項目は転送値で補完され、既存値は維持されます。
    ///
    /// 責務: 走行距離と型式の欠落補完(車両・端末は既存テストで検証済み)を確認します。
    func testImportCloudMetadataFillsMissingOdometersAndModelCode() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        var bare = GRDBConnectionSessionRepositoryFixtures.endedSession(startedAt: Date(timeIntervalSince1970: 100))
        try fixtures.repository.save(bare)
        bare.startingOdometerKilometers = 500
        bare.endingOdometerKilometers = 510
        bare.distanceSourceModelCode = "ZD8"

        try fixtures.repository.importCloudMetadata(ConnectionSessionCloudMetadata(session: bare, manifestDigest: "digest"))

        let loaded = try XCTUnwrap(fixtures.repository.sessions(for: "account").first)
        XCTAssertEqual(loaded.startingOdometerKilometers, 500)
        XCTAssertEqual(loaded.endingOdometerKilometers, 510)
        XCTAssertEqual(loaded.distanceSourceModelCode, "ZD8")
    }

    // MARK: - importCloudMetadata manifest reconciliation

    /// 既存が別Digestで `uploaded` の場合は `integrityConflict` で、`failed` なら新Digestへ更新されます。
    ///
    /// 責務: 既存Digestとの競合判定がアップロード済み状態に限られることを確認します。
    func testImportCloudMetadataDigestConflictOnlyWhenExistingIsUploaded() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 1)
        try fixtures.repository.markCloudUploaded(sessionID: session.id, manifestDigest: "local")
        let metadata = ConnectionSessionCloudMetadata(session: session, manifestDigest: "remote")

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.importCloudMetadata(metadata)
        }
        XCTAssertEqual(try fixtures.storedRecord(session.id).manifestDigest, "local")

        try fixtures.repository.markCloudUploadFailed(sessionID: session.id)
        try fixtures.repository.importCloudMetadata(metadata)

        let stored = try fixtures.storedRecord(session.id)
        XCTAssertEqual(stored.manifestDigest, "remote")
        XCTAssertEqual(stored.cloudSyncState, "uploaded")
    }

    /// 取込は件数を転送値へ更新しつつ端末側Raw保管状態を維持し、別Digestの受領証を破棄します。
    ///
    /// 責務: 件数・容量の更新、`available` の維持、受領証のDigest照合を確認します。
    func testImportCloudMetadataReconcilesCountsKeepsLocalStateAndDropsStaleReceipt() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 2)
        try fixtures.repository.markCloudUploaded(sessionID: session.id, manifestDigest: "old")
        try fixtures.repository.markMacImported(
            ConnectionSessionMacImportReceipt(
                deviceID: "mac", deviceName: "Mac", importedAt: Date(timeIntervalSince1970: 9), manifestDigest: "old"
            ),
            sessionID: session.id
        )
        try fixtures.repository.markCloudUploadFailed(sessionID: session.id)
        let remote = transferred(session) {
            $0.rawLogSummary.recordCount = 6
            $0.rawLogSummary.byteCount = 60
        }

        try fixtures.repository.importCloudMetadata(ConnectionSessionCloudMetadata(session: remote, manifestDigest: "new"))

        let stored = try fixtures.storedRecord(session.id)
        XCTAssertEqual(stored.rawRecordCount, 6)
        XCTAssertEqual(stored.rawByteCount, 60)
        XCTAssertEqual(stored.localRawState, "available")
        XCTAssertEqual(stored.manifestDigest, "new")
        XCTAssertNil(stored.macImportedManifestDigest)
    }

    // MARK: - restoreVerifiedTransfer guards

    /// 転送エントリ作成用の補助です。
    ///
    /// 責務: 指定sequenceとPayloadを持つRaw転送エントリを固定値で生成します。
    /// - Parameters:
    ///   - sequence: 記録順序。
    ///   - payload: 応答データ。
    ///   - elapsed: 経過ナノ秒。
    ///   - observedAt: 観測日時。
    /// - Returns: Raw転送エントリ。
    private func entry(
        _ sequence: Int64,
        payload: [UInt8] = [0x01],
        elapsed: UInt64 = 5,
        observedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> ConnectionSessionRawLogEntry {
        ConnectionSessionRawLogEntry(
            sequence: sequence,
            observedAt: observedAt,
            batchElapsedNanoseconds: elapsed,
            service: 0x01,
            pid: 0x0C,
            payload: payload
        )
    }

    /// 検証済み転送を生成します。
    ///
    /// 責務: 指定セッションとエントリから検証済み転送Payloadを組み立てます。
    /// - Parameters:
    ///   - session: 対象セッション。
    ///   - entries: Rawエントリ。
    ///   - digest: Manifest Digest。
    /// - Returns: 検証済み転送。
    private func transfer(
        _ session: ConnectionSession,
        entries: [ConnectionSessionRawLogEntry],
        digest: String = "digest"
    ) -> VerifiedConnectionSessionTransfer {
        VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: session, entries: entries),
            manifestDigest: digest
        )
    }

    /// sequenceが0始まりの連番でない転送は `integrityConflict` で既存Rawを変更しません。
    ///
    /// 責務: 1始まり・欠番・重複・逆順を拒否することを確認します。
    func testRestoreRejectsNonContiguousSequences() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 2)
        let invalidSets: [[ConnectionSessionRawLogEntry]] = [
            [entry(1)],
            [entry(0), entry(2)],
            [entry(0), entry(0)],
            [entry(1), entry(0)]
        ]

        for entries in invalidSets {
            assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
                try fixtures.repository.restoreVerifiedTransfer(transfer(session, entries: entries))
            }
        }
        XCTAssertEqual(try fixtures.repository.entries(for: session.id).map(\.payload), [[0], [1]])
    }

    /// 未保存セッション・アカウント不一致・未終了セッションへの復元は `integrityConflict` です。
    ///
    /// 責務: 復元先の前提を満たさない転送を拒否し、Rawを作らないことを確認します。
    func testRestoreRejectsUnknownSessionAccountMismatchAndOpenSession() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let ended = try fixtures.seedEndedSession(rawCount: 1)
        let open = ConnectionSession(accountIdentifier: "account")
        try fixtures.repository.save(open)
        let unknown = GRDBConnectionSessionRepositoryFixtures.endedSession()
        let foreign = transferred(ended) { $0 = ConnectionSession(copying: $0, account: "other") }

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.restoreVerifiedTransfer(transfer(unknown, entries: [entry(0)]))
        }
        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.restoreVerifiedTransfer(transfer(foreign, entries: [entry(0)]))
        }
        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.restoreVerifiedTransfer(transfer(open, entries: [entry(0)]))
        }
        XCTAssertEqual(try fixtures.repository.entryCount(for: unknown.id), 0)
        XCTAssertEqual(try fixtures.repository.entryCount(for: open.id), 0)
        XCTAssertEqual(try fixtures.repository.entries(for: ended.id).map(\.payload), [[0]])
    }

    /// GRDBに忠実保存できない値を含む転送は読戻し検証で拒否され、全変更がロールバックされます。
    ///
    /// 責務: 経過時間がInt64を超える転送で `integrityConflict` となり既存Rawと概要が変わらないことを確認します。
    func testRestoreRollsBackWhenReadBackDiffersFromTransfer() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 1)
        let before = try fixtures.storedRecord(session.id)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.restoreVerifiedTransfer(
                transfer(session, entries: [entry(0, payload: [0x77], elapsed: UInt64.max)], digest: "new")
            )
        }

        XCTAssertEqual(try fixtures.repository.entries(for: session.id).map(\.payload), [[0]])
        XCTAssertEqual(try fixtures.storedRecord(session.id).cloudSyncState, before.cloudSyncState)
        XCTAssertEqual(try fixtures.storedRecord(session.id).manifestDigest, before.manifestDigest)
    }

    // MARK: - restoreVerifiedTransfer success paths

    /// 既存Rawを転送内容で置換し、件数・容量・状態・Digestを転送値で更新します。
    ///
    /// 責務: 古い子行の削除と新子行の挿入、概要の再計算を確認します。
    func testRestoreReplacesExistingEntriesAndRecomputesSummary() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 3)
        let entries = [entry(0, payload: [0xAA, 0xBB]), entry(1, payload: [0xCC])]

        try fixtures.repository.restoreVerifiedTransfer(transfer(session, entries: entries, digest: "restored"))

        XCTAssertEqual(try fixtures.repository.entries(for: session.id), entries)
        let stored = try fixtures.storedRecord(session.id)
        XCTAssertEqual(stored.rawRecordCount, 2)
        XCTAssertEqual(stored.rawByteCount, 3)
        XCTAssertEqual(stored.localRawState, "available")
        XCTAssertEqual(stored.cloudSyncState, "uploaded")
        XCTAssertEqual(stored.manifestDigest, "restored")
    }

    /// 空エントリの転送は既存Rawを消し、`empty` 状態・件数0になります。
    ///
    /// 責務: 空転送時の状態と子行削除を確認します。
    func testRestoreWithEmptyEntriesClearsRawAndMarksEmpty() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 2)

        try fixtures.repository.restoreVerifiedTransfer(transfer(session, entries: []))

        let stored = try fixtures.storedRecord(session.id)
        XCTAssertEqual(stored.localRawState, "empty")
        XCTAssertEqual(stored.rawRecordCount, 0)
        XCTAssertEqual(stored.rawByteCount, 0)
        XCTAssertEqual(try fixtures.repository.entryCount(for: session.id), 0)
    }

    /// 受領証は同じDigestの場合だけ残り、閲覧日時は常に保持されます。
    ///
    /// 責務: 復元時のMac受領証のDigest照合と最終閲覧日時の引継ぎを確認します。
    func testRestoreKeepsReceiptOnlyForSameDigestAndPreservesLastAccess() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 1)
        try fixtures.repository.markCloudUploaded(sessionID: session.id, manifestDigest: "digest")
        try fixtures.repository.markMacImported(
            ConnectionSessionMacImportReceipt(
                deviceID: "mac", deviceName: "Mac", importedAt: Date(timeIntervalSince1970: 9), manifestDigest: "digest"
            ),
            sessionID: session.id
        )
        let accessed = Date(timeIntervalSince1970: 4_321)
        try fixtures.repository.markRawLogAccessed(at: accessed, sessionID: session.id)

        try fixtures.repository.restoreVerifiedTransfer(transfer(session, entries: [entry(0)], digest: "digest"))
        XCTAssertEqual(try fixtures.storedRecord(session.id).macImportedManifestDigest, "digest")
        XCTAssertEqual(try fixtures.storedRecord(session.id).rawLastAccessedAt, accessed)

        try fixtures.repository.restoreVerifiedTransfer(transfer(session, entries: [entry(0)], digest: "different"))
        XCTAssertNil(try fixtures.storedRecord(session.id).macImportedManifestDigest)
        XCTAssertEqual(try fixtures.storedRecord(session.id).rawLastAccessedAt, accessed)
    }

    /// ミリ秒未満の観測日時はGRDBの丸めを許容して復元できます。
    ///
    /// 責務: 1ミリ秒以内の日時差を不一致としないことを確認します。
    func testRestoreAcceptsSubMillisecondObservedAtDifference() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 0)
        let precise = entry(0, observedAt: Date(timeIntervalSince1970: 1_000.123_4))

        try fixtures.repository.restoreVerifiedTransfer(transfer(session, entries: [precise]))

        let stored = try XCTUnwrap(fixtures.repository.entries(for: session.id).first)
        XCTAssertEqual(stored.observedAt.timeIntervalSince1970, 1_000.123_4, accuracy: 0.001)
        XCTAssertEqual(stored.payload, precise.payload)
    }
}

private extension ConnectionSession {
    /// アカウントまたは開始日時だけを差し替えた同一IDのセッション複製を作ります。
    ///
    /// 責務: `let` で保持される項目を除き全フィールドを引き継いだ複製を返します。
    /// - Parameters:
    ///   - source: 複製元。
    ///   - account: 差し替えるアカウント識別子。省略時は元の値。
    ///   - startedAt: 差し替える開始日時。省略時は元の値。
    init(copying source: ConnectionSession, account: String? = nil, startedAt: Date? = nil) {
        self.init(
            id: source.id,
            accountIdentifier: account ?? source.accountIdentifier,
            startedAt: startedAt ?? source.startedAt,
            vehicle: source.vehicle,
            acquisitionDevice: source.acquisitionDevice
        )
        endedAt = source.endedAt
        endReason = source.endReason
        stopReviewDecision = source.stopReviewDecision
        startingOdometerKilometers = source.startingOdometerKilometers
        endingOdometerKilometers = source.endingOdometerKilometers
        distanceSourceModelCode = source.distanceSourceModelCode
        rawLogSummary = source.rawLogSummary
    }
}
