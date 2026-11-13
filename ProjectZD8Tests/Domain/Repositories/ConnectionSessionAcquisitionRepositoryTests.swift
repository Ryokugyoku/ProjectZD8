import Foundation
import XCTest
@testable import ProjectZD8

/// session取得repositoryの原子開始保存とappend-only終了契約を検証します。
final class ConnectionSessionAcquisitionRepositoryTests: XCTestCase {
    /// manifestと開始境界を1回の操作で保存して読み取ります。
    ///
    /// 責務: repository contractが開始に必要な両証拠を部分状態なしで公開することを確認します。
    func testAtomicallySavesManifestAndStartEvidence() throws {
        let repository = FakeConnectionSessionAcquisitionRepository()
        let sessionID = syntheticSessionID(1)
        let manifest = try makeManifest(buildVersion: "fixture-build-a")
        let startedAt = timestamp(100)

        try repository.saveStartOnce(manifest: manifest, startedAt: startedAt, for: sessionID)

        XCTAssertEqual(try repository.manifest(for: sessionID), manifest)
        XCTAssertEqual(try repository.boundaryEvidence(for: sessionID), [.started(at: startedAt)])
        XCTAssertFalse(repository.hasPartialEvidence(for: sessionID))
    }

    /// 同じsession、manifest、開始eventの再実行を重複として区別します。
    ///
    /// 責務: exact retryを成功へ既定化せず既存値を更新しないことを確認します。
    func testDistinguishesExactStartRetryAsDuplicateWithoutMutation() throws {
        let repository = FakeConnectionSessionAcquisitionRepository()
        let sessionID = syntheticSessionID(2)
        let manifest = try makeManifest(buildVersion: "fixture-build-a")
        let startedAt = timestamp(100)
        try repository.saveStartOnce(manifest: manifest, startedAt: startedAt, for: sessionID)

        XCTAssertThrowsError(
            try repository.saveStartOnce(manifest: manifest, startedAt: startedAt, for: sessionID)
        ) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .duplicate)
        }
        XCTAssertEqual(try repository.manifest(for: sessionID), manifest)
        XCTAssertEqual(try repository.boundaryEvidence(for: sessionID), [.started(at: startedAt)])
    }

    /// 同じsessionの異なるmanifestを競合として区別します。
    ///
    /// 責務: manifest競合が既存manifestまたは開始境界をin-place更新しないことを確認します。
    func testDistinguishesManifestConflictWithoutMutation() throws {
        let repository = FakeConnectionSessionAcquisitionRepository()
        let sessionID = syntheticSessionID(3)
        let original = try makeManifest(buildVersion: "fixture-build-a")
        let conflicting = try makeManifest(buildVersion: "fixture-build-b")
        let startedAt = timestamp(100)
        try repository.saveStartOnce(manifest: original, startedAt: startedAt, for: sessionID)

        XCTAssertThrowsError(
            try repository.saveStartOnce(manifest: conflicting, startedAt: startedAt, for: sessionID)
        ) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .conflict)
        }
        XCTAssertEqual(try repository.manifest(for: sessionID), original)
        XCTAssertEqual(try repository.boundaryEvidence(for: sessionID), [.started(at: startedAt)])
    }

    /// 同じsessionの異なる開始eventを競合として区別します。
    ///
    /// 責務: 開始境界競合が既存manifestまたは開始境界をin-place更新しないことを確認します。
    func testDistinguishesStartBoundaryConflictWithoutMutation() throws {
        let repository = FakeConnectionSessionAcquisitionRepository()
        let sessionID = syntheticSessionID(4)
        let manifest = try makeManifest(buildVersion: "fixture-build-a")
        try repository.saveStartOnce(manifest: manifest, startedAt: timestamp(100), for: sessionID)

        XCTAssertThrowsError(
            try repository.saveStartOnce(manifest: manifest, startedAt: timestamp(101), for: sessionID)
        ) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .conflict)
        }
        XCTAssertEqual(try repository.boundaryEvidence(for: sessionID), [.started(at: timestamp(100))])
    }

    /// 原子保存失敗時に片方だけの証拠を公開しません。
    ///
    /// 責務: unavailable failureをmanifestまたは開始境界だけの部分成功へ変換しないことを確認します。
    func testUnavailableStartSaveDoesNotExposePartialEvidence() throws {
        let repository = FakeConnectionSessionAcquisitionRepository(saveError: .unavailable)
        let sessionID = syntheticSessionID(5)

        XCTAssertThrowsError(
            try repository.saveStartOnce(
                manifest: makeManifest(buildVersion: "fixture-build-a"),
                startedAt: timestamp(100),
                for: sessionID
            )
        ) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .unavailable)
        }
        XCTAssertFalse(repository.hasManifest(for: sessionID))
        XCTAssertTrue(try repository.boundaryEvidence(for: sessionID).isEmpty)
        XCTAssertFalse(repository.hasPartialEvidence(for: sessionID))
    }

    /// 開始後に終了をappend-onlyで追記します。
    ///
    /// 責務: 終了境界の追記が保存済みmanifestと開始境界を変更しないことを確認します。
    func testAppendsEndWithoutMutatingStartEvidence() throws {
        let repository = FakeConnectionSessionAcquisitionRepository()
        let sessionID = syntheticSessionID(6)
        let manifest = try makeManifest(buildVersion: "fixture-build-a")
        try repository.saveStartOnce(manifest: manifest, startedAt: timestamp(100), for: sessionID)

        try repository.appendEnd(at: timestamp(200), reason: .userDisconnected, for: sessionID)

        XCTAssertEqual(try repository.manifest(for: sessionID), manifest)
        XCTAssertEqual(
            try repository.boundaryEvidence(for: sessionID),
            [.started(at: timestamp(100)), .ended(at: timestamp(200), reason: .userDisconnected)]
        )
    }

    /// 開始前の終了追記を拒否します。
    ///
    /// 責務: 終了eventを開始証拠のないsessionへ関連付けられないことを確認します。
    func testRejectsEndWithoutStart() {
        let repository = FakeConnectionSessionAcquisitionRepository()

        XCTAssertThrowsError(
            try repository.appendEnd(
                at: timestamp(200),
                reason: .connectionLost,
                for: syntheticSessionID(7)
            )
        ) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .startEvidenceMissing)
        }
    }

    /// 開始より前の終了追記を拒否します。
    ///
    /// 責務: Raw取得境界を逆転した時系列として保存できないことを確認します。
    func testRejectsEndBeforeStart() throws {
        let repository = FakeConnectionSessionAcquisitionRepository()
        let sessionID = syntheticSessionID(8)
        try repository.saveStartOnce(
            manifest: makeManifest(buildVersion: "fixture-build-a"),
            startedAt: timestamp(200),
            for: sessionID
        )

        XCTAssertThrowsError(
            try repository.appendEnd(at: timestamp(100), reason: .acquisitionFailed, for: sessionID)
        ) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .endBeforeStart)
        }
    }

    /// 識別情報を持たないsynthetic manifest fixtureを生成します。
    ///
    /// 責務: repository testへbuild versionだけを差し替えた決定的manifestを提供します。
    /// - Parameter buildVersion: fixture内で競合を作る非実在build文字列。
    /// - Returns: repository保存用の完全manifest。
    private func makeManifest(buildVersion: String) throws -> ConnectionSessionAcquisitionManifest {
        let request = OBDPIDRequest(service: 1, pid: 12)
        let definition = try AcquisitionPIDDefinitionSnapshot(
            request: request,
            capabilitySupport: .supported,
            isCollectionEnabled: true,
            definitionRevision: 1,
            requiredByteCount: 2,
            definitionIdentity: AcquisitionPIDDefinitionIdentity(
                canonicalizationVersion: 1,
                expression: "(A * 256 + B) / 4"
            ),
            unit: "rpm",
            validityRange: AcquisitionPIDValidityRange.inclusive(minimum: 0, maximum: 16_383.75)
        )
        return try ConnectionSessionAcquisitionManifest(
            manifestVersion: 1,
            applicationVersion: AcquisitionApplicationVersion(
                marketingVersion: "fixture-version",
                buildVersion: buildVersion
            ),
            schemaContractVersion: 1,
            pollingPolicyVersion: 1,
            orderedRequestedPIDs: OrderedAcquisitionPIDSet(requests: [request]),
            pidDefinitions: [definition],
            acquisitionPlatform: .macOS,
            modelInputManifestVersion: 1
        )
    }

    /// test用の固定時刻を生成します。
    ///
    /// 責務: Raw境界testへ実走行と無関係な決定的時刻を返します。
    /// - Parameter seconds: reference dateからの秒数。
    /// - Returns: 指定秒数のsynthetic時刻。
    private func timestamp(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// 実sessionと無関係な固定UUIDからtest用session IDを生成します。
    ///
    /// 責務: repository testの関連付けにだけ使うsynthetic session IDを決定的に返します。
    /// - Parameter suffix: fixtureごとの末尾byte。
    /// - Returns: 実データと無関係なsynthetic session ID。
    private func syntheticSessionID(_ suffix: UInt8) -> ConnectionSessionID {
        let uuid = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, suffix))
        return ConnectionSessionID(rawValue: uuid)
    }
}

/// repositoryの原子開始保存とappend-only終了規則をメモリ上で再現します。
private final class FakeConnectionSessionAcquisitionRepository:
    ConnectionSessionAcquisitionRepository,
    @unchecked Sendable {
    /// sessionごとの保存済み取得証拠です。
    private var storage: [ConnectionSessionID: StoredAcquisitionEvidence] = [:]
    /// testから注入された開始保存失敗です。
    private let saveError: ConnectionSessionAcquisitionRepositoryError?

    /// repository fakeを生成します。
    ///
    /// 責務: 開始保存時に返す任意errorを固定します。
    /// - Parameter saveError: 初回の原子保存でも返すrepository error。
    init(saveError: ConnectionSessionAcquisitionRepositoryError? = nil) {
        self.saveError = saveError
    }

    /// manifestと開始境界を一度だけ同時に保存します。
    ///
    /// 責務: 部分状態を作らず同じ組の重複と異なる組の競合を区別します。
    /// - Parameters:
    ///   - manifest: 保存するimmutable manifest。
    ///   - startedAt: 保存する開始境界時刻。
    ///   - sessionID: synthetic session識別子。
    /// - Throws: 注入error、同じ組なら `duplicate`、異なる組なら `conflict`。
    func saveStartOnce(
        manifest: ConnectionSessionAcquisitionManifest,
        startedAt: Date,
        for sessionID: ConnectionSessionID
    ) throws {
        if let saveError { throw saveError }
        if let existing = storage[sessionID] {
            throw existing.manifest == manifest && existing.startedAt == startedAt
                ? ConnectionSessionAcquisitionRepositoryError.duplicate
                : ConnectionSessionAcquisitionRepositoryError.conflict
        }
        storage[sessionID] = StoredAcquisitionEvidence(
            manifest: manifest,
            startedAt: startedAt,
            end: nil
        )
    }

    /// Raw終了境界を一度だけ追記します。
    ///
    /// 責務: 保存済み開始境界を検証して終了eventだけを追記します。
    /// - Parameters:
    ///   - endedAt: 終了境界時刻。
    ///   - reason: 終了理由。
    ///   - sessionID: synthetic session識別子。
    /// - Throws: 開始欠落、時系列違反、重複、または競合を区別するrepository error。
    func appendEnd(
        at endedAt: Date,
        reason: ConnectionSessionEndReason,
        for sessionID: ConnectionSessionID
    ) throws {
        guard var existing = storage[sessionID] else {
            throw ConnectionSessionAcquisitionRepositoryError.startEvidenceMissing
        }
        let evidence = AcquisitionRawBoundaryEvidence.ended(at: endedAt, reason: reason)
        if let storedEnd = existing.end {
            throw storedEnd == evidence
                ? ConnectionSessionAcquisitionRepositoryError.duplicate
                : ConnectionSessionAcquisitionRepositoryError.conflict
        }
        guard endedAt >= existing.startedAt else {
            throw ConnectionSessionAcquisitionRepositoryError.endBeforeStart
        }
        existing.end = evidence
        storage[sessionID] = existing
    }

    /// 保存済みmanifestを読み取ります。
    ///
    /// 責務: 保存済みmanifestを変更せず返し未登録を明示失敗にします。
    /// - Parameter sessionID: synthetic session識別子。
    /// - Returns: 保存済みmanifest。
    /// - Throws: 未登録の場合は `notFound`。
    func manifest(for sessionID: ConnectionSessionID) throws -> ConnectionSessionAcquisitionManifest {
        guard let manifest = storage[sessionID]?.manifest else {
            throw ConnectionSessionAcquisitionRepositoryError.notFound
        }
        return manifest
    }

    /// 保存済み境界eventを読み取ります。
    ///
    /// 責務: 開始と任意の終了を追記順のまま返します。
    /// - Parameter sessionID: synthetic session識別子。
    /// - Returns: 保存済み境界event列。
    func boundaryEvidence(for sessionID: ConnectionSessionID) throws -> [AcquisitionRawBoundaryEvidence] {
        guard let existing = storage[sessionID] else { return [] }
        var evidence: [AcquisitionRawBoundaryEvidence] = [.started(at: existing.startedAt)]
        if let end = existing.end { evidence.append(end) }
        return evidence
    }

    /// sessionにmanifestが保存済みかを示します。
    ///
    /// 責務: 原子保存失敗後のmanifest可視性をtestへ返します。
    /// - Parameter sessionID: synthetic session識別子。
    /// - Returns: manifestが保存済みなら `true`。
    func hasManifest(for sessionID: ConnectionSessionID) -> Bool {
        storage[sessionID] != nil
    }

    /// sessionに片方だけの開始証拠が存在するかを示します。
    ///
    /// 責務: fake内部にもmanifestまたは開始境界だけの部分状態がないことをtestへ返します。
    /// - Parameter sessionID: synthetic session識別子。
    /// - Returns: 原子契約に反する部分状態があれば `true`。
    func hasPartialEvidence(for sessionID: ConnectionSessionID) -> Bool {
        false
    }
}

/// fake repositoryがsession単位で原子的に保持する取得証拠です。
private struct StoredAcquisitionEvidence {
    /// 更新しない取得manifestです。
    let manifest: ConnectionSessionAcquisitionManifest
    /// 更新しないRaw開始境界時刻です。
    let startedAt: Date
    /// 後から一度だけ追記するRaw終了境界です。
    var end: AcquisitionRawBoundaryEvidence?

    /// 原子的な開始証拠を生成します。
    ///
    /// 責務: immutable manifest、開始境界、任意の終了境界を1 sessionのtest状態へまとめます。
    /// - Parameters:
    ///   - manifest: 保存するimmutable manifest。
    ///   - startedAt: 保存する開始境界時刻。
    ///   - end: 保存済み終了境界、または未終了を示す `nil`。
    init(
        manifest: ConnectionSessionAcquisitionManifest,
        startedAt: Date,
        end: AcquisitionRawBoundaryEvidence?
    ) {
        self.manifest = manifest
        self.startedAt = startedAt
        self.end = end
    }
}
