import Foundation
import XCTest
@testable import ProjectZD8

/// 取得記録が開始入力のアダプター判定結果をmanifestへ保存することと、判定結果の違う取得でプロセス復帰後に
/// 同じセッションを続けられること(区間・連番・batch番号が続き、保存済みmanifestは最初の値のまま)をメモリ上のGRDBで検証します。
@MainActor
final class ConnectionSessionAcquisitionRecorderContinuationTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture
    /// 常駐リンクの初期化で判定した結果です。
    private let probe = AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: .framesReceived)
    /// 最後にcommitしたRawの実時刻です。
    private let lastCommittedAt = Date(timeIntervalSince1970: 1_020)

    /// 開始入力の判定結果(あり・なし)が、保存されたmanifestへそのまま入ります。
    ///
    /// 責務: 取得記録が判定結果を落とさず、補完もしないことを確認します。
    func testStartPersistsProbeEvidenceInManifest() async throws {
        let withProbe = try Fixture(storage: .grdb)
        let withoutProbe = try Fixture(storage: .grdb)

        try await withProbe.recorder.start(startInput(probe: probe))
        try await withoutProbe.recorder.start(startInput(probe: nil))

        XCTAssertEqual(try withProbe.acquisition.manifest(for: withProbe.sessionID).adapterProbeEvidence, probe)
        XCTAssertNil(try withoutProbe.acquisition.manifest(for: withoutProbe.sessionID).adapterProbeEvidence)
    }

    /// 判定結果ありで始めたセッションを、プロセス復帰後に判定結果なしで続けると、開始が成功し区間と連番が続きます。
    ///
    /// 責務: 常駐リンク→手動接続の続行で取得が保存失敗にならず、保存済みmanifestの判定結果が残ることを確認します。
    func testProbeStartedSessionContinuesWithoutProbeAfterRelaunch() async throws {
        let fixture = try await makeInterruptedSession(probe: probe)

        try await resume(fixture, probe: nil)

        try assertContinued(fixture)
        XCTAssertEqual(try fixture.acquisition.manifest(for: fixture.sessionID).adapterProbeEvidence, probe)
    }

    /// 判定結果なしで始めたセッションを、プロセス復帰後に判定結果ありで続けると、開始が成功し区間と連番が続きます。
    ///
    /// 責務: 手動接続→常駐リンクの続行で取得が保存失敗にならず、保存済みmanifestが判定結果なしのまま残ることを確認します。
    func testProbelessSessionContinuesWithProbeAfterRelaunch() async throws {
        let fixture = try await makeInterruptedSession(probe: nil)

        try await resume(fixture, probe: probe)

        try assertContinued(fixture)
        XCTAssertNil(try fixture.acquisition.manifest(for: fixture.sessionID).adapterProbeEvidence)
    }

    // MARK: - Helpers

    /// 2PIDの開始入力を返します。
    ///
    /// 責務: 部品の定義・収集有効capability・manifest順の要求列と、指定の判定結果で開始入力を作ります。
    /// - Parameter probe: アダプター判定結果。
    /// - Returns: 世代1の開始入力。
    private func startInput(probe: AcquisitionAdapterProbeEvidence?) -> LiveTelemetryAcquisitionStartInput {
        let requests = Fixture.definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }
        return LiveTelemetryAcquisitionStartInput(
            generation: 1,
            definitions: Fixture.definitions,
            capabilities: requests.map { .init(request: $0, support: .supported, isCollectionEnabled: true) },
            orderedRequests: requests,
            adapterProbeEvidence: probe
        )
    }

    /// 指定の判定結果で2周回を記録してcommitし、終了せずにプロセスが終わった状態を作ります。
    ///
    /// 責務: 最後のRawの実時刻を `lastCommittedAt` にした未終了セッションを返します。
    /// - Parameter probe: 最初の取得のアダプター判定結果。
    /// - Returns: GRDBの部品。
    /// - Throws: 記録の失敗。
    private func makeInterruptedSession(probe: AcquisitionAdapterProbeEvidence?) async throws -> Fixture {
        let fixture = try Fixture(storage: .grdb)
        try await fixture.recorder.start(startInput(probe: probe))
        fixture.dates.set(Date(timeIntervalSince1970: 1_010))
        try await fixture.respondedRound(0, payload: 10)
        fixture.dates.set(lastCommittedAt)
        try await fixture.respondedRound(1, payload: 20)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)
        return fixture
    }

    /// 猶予内のプロセス復帰として続行可能にし、作り直した取得記録を指定の判定結果で開始して1周回を保存します。
    ///
    /// 責務: 復帰処理で続行可能と判定されたことを確かめてから、続きの取得を記録します。
    /// - Parameters:
    ///   - fixture: GRDBの部品。
    ///   - probe: 続きの取得のアダプター判定結果。
    /// - Throws: 復帰処理または記録の失敗。
    private func resume(_ fixture: Fixture, probe: AcquisitionAdapterProbeEvidence?) async throws {
        let recovery = RecoverRelaunchedConnectionSessionUseCase(
            rawLogRepository: fixture.sessions, segmentRepository: fixture.segments,
            gapRepository: fixture.gaps, terminationRepository: fixture.acquisition
        )
        let session = try XCTUnwrap(fixture.sessions.sessions(for: "account").first { $0.id == fixture.sessionID })
        let outcome = try recovery.recover(session, now: lastCommittedAt.addingTimeInterval(60))
        guard case .resumable = outcome else { return XCTFail("続行可能になりませんでした: \(outcome)") }
        fixture.relaunchRecorder()
        fixture.dates.set(Date(timeIntervalSince1970: 1_150))
        try await fixture.recorder.start(startInput(probe: probe))
        try await fixture.respondedRound(0, payload: 30)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)
    }

    /// 続きの取得が同じセッションの続きとして保存されたことを確認します。
    ///
    /// 責務: 区間の開始理由、Rawの連番、batch番号が既存の続きであることを検証します。
    /// - Parameter fixture: GRDBの部品。
    /// - Throws: 読込失敗。
    private func assertContinued(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) throws {
        let segments = try fixture.segments.segments(for: fixture.sessionID)
        XCTAssertEqual(segments.map(\.startReason), [.initial, .processRelaunched], file: file, line: line)
        XCTAssertEqual(try fixture.storedRaws().map(\.sequence), [0, 1, 2], file: file, line: line)
        XCTAssertEqual(try fixture.storedRaws().map(\.payload), [[10], [20], [30]], file: file, line: line)
        XCTAssertEqual(
            try fixture.acquisition.batches(for: fixture.sessionID).map(\.identity.ordinal), [0, 1, 2], file: file, line: line
        )
    }
}
