import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `CreateConnectionSessionAcquisitionManifestUseCase.execute` の続行の経路(保存済みmanifestのあるセッションへの再開始)を検証します。
///
/// 仕様: 続行時の比較はアダプター判定結果だけを除き、続行できる時は保存済みmanifestをそのまま使い、書き換えない。
@MainActor
final class CreateConnectionSessionAcquisitionManifestUseCaseContinuationTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias F = AcquisitionManifestContinuationFixture
    /// 常駐リンクの初期化で判定した結果です。
    private let probe = F.stnFrames
    /// 最初の開始時刻です。
    private let firstStart = Date(timeIntervalSince1970: 100)
    /// 続きの開始時刻です。
    private let laterStart = Date(timeIntervalSince1970: 200)

    /// 判定結果ありで保存したセッションを判定結果なしで続けると成功し、許可のmanifestは保存済みの値(判定結果あり)です。
    ///
    /// 責務: 常駐リンク→手動接続の続行で、保存済みmanifest・開始境界が書き換わらないことをGRDBで確認します。
    func testStoredProbeContinuesWithoutProbeUsingStoredManifest() async throws {
        let (acquisition, sessionID) = try makeGRDB()
        let first = try await execute(acquisition, sessionID: sessionID, probe: probe, at: firstStart, generation: 1)

        let continued = try await execute(acquisition, sessionID: sessionID, probe: nil, at: laterStart, generation: 2)

        XCTAssertEqual(continued.manifest, first.manifest)
        XCTAssertEqual(continued.manifest.adapterProbeEvidence, probe)
        XCTAssertEqual(continued.generation, 2)
        XCTAssertEqual(try acquisition.manifest(for: sessionID).adapterProbeEvidence, probe)
        XCTAssertEqual(try acquisition.boundaryEvidence(for: sessionID), [.started(at: firstStart)])
    }

    /// 判定結果なしで保存したセッションを判定結果ありで続けると成功し、許可のmanifestは保存済みの値(判定結果なし)です。
    ///
    /// 責務: 手動接続→常駐リンクの続行で、後から来た判定結果で保存済みmanifestを上書きしないことをGRDBで確認します。
    func testStoredWithoutProbeContinuesWithProbeUsingStoredManifest() async throws {
        let (acquisition, sessionID) = try makeGRDB()
        _ = try await execute(acquisition, sessionID: sessionID, probe: nil, at: firstStart, generation: 1)

        let continued = try await execute(acquisition, sessionID: sessionID, probe: probe, at: laterStart, generation: 2)

        XCTAssertNil(continued.manifest.adapterProbeEvidence)
        XCTAssertNil(try acquisition.manifest(for: sessionID).adapterProbeEvidence)
        XCTAssertEqual(try acquisition.boundaryEvidence(for: sessionID), [.started(at: firstStart)])
    }

    /// 判定結果のほかに契約versionも違えば、続行せず競合として失敗し、保存済みmanifestは変わりません。
    ///
    /// 責務: 判定結果の除外が他項目の不一致を成功へ変えないことをGRDBで確認します。
    func testOtherDifferenceWithProbeDifferenceIsConflict() async throws {
        let (acquisition, sessionID) = try makeGRDB()
        let first = try await execute(acquisition, sessionID: sessionID, probe: probe, at: firstStart, generation: 1)

        let error = await capturedError {
            try await self.execute(acquisition, sessionID: sessionID, probe: nil, at: self.laterStart, generation: 2, manifestVersion: 2)
        }

        XCTAssertEqual(error, .conflict)
        XCTAssertEqual(try acquisition.manifest(for: sessionID), first.manifest)
    }

    /// 保存済みmanifestの無いセッションでは新規に保存し、許可のmanifestは要求の判定結果を持ちます(あり・なしの両方)。
    ///
    /// 責務: 競合の無い初回保存では要求側の値がそのまま保存・返却されることを確認します。
    func testFirstSaveUsesRequestedProbe() async throws {
        let (withProbe, withProbeSession) = try makeGRDB()
        let (withoutProbe, withoutProbeSession) = try makeGRDB()

        let saved = try await execute(withProbe, sessionID: withProbeSession, probe: probe, at: firstStart, generation: 1)
        let savedWithout = try await execute(withoutProbe, sessionID: withoutProbeSession, probe: nil, at: firstStart, generation: 1)

        XCTAssertEqual(saved.manifest.adapterProbeEvidence, probe)
        XCTAssertEqual(try withProbe.manifest(for: withProbeSession).adapterProbeEvidence, probe)
        XCTAssertNil(savedWithout.manifest.adapterProbeEvidence)
        XCTAssertNil(try withoutProbe.manifest(for: withoutProbeSession).adapterProbeEvidence)
    }

    /// 保存が `duplicate`(同じ開始境界の再試行)を返し、違いが判定結果だけなら保存済みmanifestで続行します。
    ///
    /// 責務: `duplicate` の入口でも続行判定を通して保存済みの値を返し、拒まれた保存1回の後に保存をやり直さない
    /// (保存済みmanifestを上書きする呼び出しが無い)ことを確認します。
    func testDuplicateEntryContinuesWithStoredManifest() async throws {
        let stub = ScriptedStartAcquisitionRepositoryStub()
        let sessionID = ConnectionSessionID()
        _ = try await execute(stub, sessionID: sessionID, probe: probe, at: firstStart, generation: 1)
        stub.saveError = .duplicate

        let continued = try await execute(stub, sessionID: sessionID, probe: nil, at: firstStart, generation: 1)

        XCTAssertEqual(continued.manifest.adapterProbeEvidence, probe)
        XCTAssertEqual(stub.saveAttempts.map(\.manifest.adapterProbeEvidence), [probe, nil])
        XCTAssertEqual(stub.saveAttempts.map(\.startedAt), [firstStart, firstStart])
    }

    /// 保存が `conflict`(開始境界が違う続き)を返し、違いが判定結果だけなら保存済みmanifestで続行します。
    ///
    /// 責務: `conflict` の入口で続行判定を通して保存済みの値を返し、拒まれた保存1回の後に保存をやり直さないことを確認します。
    func testConflictEntryContinuesWithStoredManifest() async throws {
        let stub = ScriptedStartAcquisitionRepositoryStub()
        let sessionID = ConnectionSessionID()
        _ = try await execute(stub, sessionID: sessionID, probe: nil, at: firstStart, generation: 1)
        stub.saveError = .conflict

        let continued = try await execute(stub, sessionID: sessionID, probe: probe, at: laterStart, generation: 2)

        XCTAssertNil(continued.manifest.adapterProbeEvidence)
        XCTAssertEqual(stub.saveAttempts.map(\.manifest.adapterProbeEvidence), [nil, probe])
        XCTAssertEqual(stub.saveAttempts.map(\.startedAt), [firstStart, laterStart])
    }

    /// `duplicate` の入口でも、判定結果以外が違えば競合として失敗します。
    ///
    /// 責務: 同じ開始境界の再試行でも内容の違うmanifestを成功にしないことを確認します。
    func testDuplicateEntryWithOtherDifferenceIsConflict() async throws {
        let stub = ScriptedStartAcquisitionRepositoryStub()
        let sessionID = ConnectionSessionID()
        _ = try await execute(stub, sessionID: sessionID, probe: probe, at: firstStart, generation: 1)
        stub.saveError = .duplicate

        let error = await capturedError {
            try await self.execute(stub, sessionID: sessionID, probe: self.probe, at: self.firstStart, generation: 1, manifestVersion: 2)
        }

        XCTAssertEqual(error, .conflict)
    }

    /// 保存が競合を返したのに保存済みmanifestが読めなければ、その失敗(`notFound`)をそのまま返します。
    ///
    /// 責務: 保存済みmanifestの欠落を成功や要求側の値へ潰さないことを確認します。
    func testConflictWithoutStoredManifestPropagatesNotFound() async throws {
        let stub = ScriptedStartAcquisitionRepositoryStub()
        stub.saveError = .conflict

        let error = await capturedError {
            try await self.execute(stub, sessionID: ConnectionSessionID(), probe: nil, at: self.firstStart, generation: 1)
        }

        XCTAssertEqual(error, .notFound)
    }

    /// `duplicate`・`conflict` 以外の保存失敗は、続行判定を通さずにそのまま返します。
    ///
    /// 責務: 保存先の利用不能を、保存済みmanifestがあっても続行扱いにしないことを確認します。
    func testUnavailableIsNotTreatedAsContinuation() async throws {
        let stub = ScriptedStartAcquisitionRepositoryStub()
        let sessionID = ConnectionSessionID()
        _ = try await execute(stub, sessionID: sessionID, probe: nil, at: firstStart, generation: 1)
        stub.saveError = .unavailable

        let error = await capturedError {
            try await self.execute(stub, sessionID: sessionID, probe: nil, at: self.laterStart, generation: 2)
        }

        XCTAssertEqual(error, .unavailable)
    }

    // MARK: - Helpers

    /// 未終了セッション1件を保存したメモリ上のGRDBの取得証跡保存先を返します。
    ///
    /// 責務: manifestの外部キー先となる接続セッションを保存してから保存先を返します。
    /// - Returns: 取得証跡の保存先とセッションID。
    /// - Throws: DB作成・保存の失敗。
    private func makeGRDB() throws -> (GRDBConnectionSessionAcquisitionRepository, ConnectionSessionID) {
        let queue = try DatabaseQueue()
        let sessions = try GRDBConnectionSessionRepository(databaseQueue: queue)
        let sessionID = ConnectionSessionID()
        try sessions.save(ConnectionSession(id: sessionID, accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 1)))
        return (try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue), sessionID)
    }

    /// 新しいuse caseで1世代分のmanifest作成を実行します。
    ///
    /// 責務: 指定の開始時刻を返す時計で世代を有効化し、2PIDの入力で `execute` を呼びます。
    /// - Parameters:
    ///   - repository: 取得証跡の保存先。
    ///   - sessionID: セッションID。
    ///   - probe: 入力のアダプター判定結果。
    ///   - startedAt: 開始境界の時刻。
    ///   - generation: 世代。
    ///   - manifestVersion: manifest version。
    /// - Returns: Raw取得の許可。
    /// - Throws: use caseの失敗。
    private func execute(
        _ repository: any ConnectionSessionAcquisitionRepository,
        sessionID: ConnectionSessionID,
        probe: AcquisitionAdapterProbeEvidence?,
        at startedAt: Date,
        generation: UInt,
        manifestVersion: Int = 1
    ) async throws -> ConnectionSessionRawAcquisitionPermission {
        let useCase = CreateConnectionSessionAcquisitionManifestUseCase(
            acquisitionRepository: repository, evidencePort: FixedAcquisitionRuntimeEvidencePort(), now: { startedAt }
        )
        await useCase.activate(generation: generation)
        let definitions = ConnectionSessionAcquisitionRecorderFixture.definitions
        let requests = definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }
        return try await useCase.execute(
            CreateConnectionSessionAcquisitionManifestInput(
                sessionID: sessionID, generation: generation, manifestVersion: manifestVersion, pollingPolicyVersion: 2,
                modelInputManifestVersion: 1, formulaCanonicalizationVersion: 1, pidDefinitions: definitions,
                pidCapabilities: requests.map { .init(request: $0, support: .supported, isCollectionEnabled: true) },
                orderedRequestedPIDs: requests, adapterProbeEvidence: probe
            )
        )
    }

    /// 処理が投げた保存先の失敗を返します。
    ///
    /// 責務: 成功・別種の失敗はテスト失敗として報告し、保存先の失敗だけを比較できる値にします。
    /// - Parameter operation: 実行する処理。
    /// - Returns: 保存先の失敗。成功・別種の失敗なら `nil`。
    private func capturedError(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> ConnectionSessionRawAcquisitionPermission
    ) async -> ConnectionSessionAcquisitionRepositoryError? {
        do {
            _ = try await operation()
            XCTFail("失敗せずに許可が返りました", file: file, line: line)
            return nil
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            return error
        } catch {
            XCTFail("想定外の失敗: \(error)", file: file, line: line)
            return nil
        }
    }
}
