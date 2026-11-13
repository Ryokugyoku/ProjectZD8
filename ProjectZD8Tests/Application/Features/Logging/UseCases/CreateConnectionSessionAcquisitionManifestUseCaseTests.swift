import Foundation
import XCTest
@testable import ProjectZD8

/// session取得manifest作成とRaw開始許可のApplication orchestrationを検証します。
final class CreateConnectionSessionAcquisitionManifestUseCaseTests: XCTestCase {
    /// 完全な入力と開始境界を1回のrepository callで保存します。
    ///
    /// 責務: 完全manifestと開始eventの原子保存成功だけが同一世代のRaw開始許可を返すことを確認します。
    func testSavesCompleteManifestOnceBeforeAllowingRawAcquisition() async throws {
        let fixture = makeFixture()
        let permission = try await fixture.execute()

        XCTAssertEqual(permission.sessionID, fixture.input.sessionID)
        XCTAssertEqual(permission.generation, fixture.input.generation)
        XCTAssertEqual(fixture.acquisitionRepository.saveStartCallCount, 1)
        XCTAssertEqual(fixture.acquisitionRepository.storedManifest, permission.manifest)
        XCTAssertEqual(fixture.acquisitionRepository.storedStartedAt, fixture.startedAt)
    }

    /// runtimeと明示versionをmanifestへそのまま伝播します。
    ///
    /// 責務: app/build/schema/manifest/polling/model-input versionを推測なしで保存値へ反映します。
    func testPropagatesAllVersionAuthorities() async throws {
        let fixture = makeFixture()
        let manifest = try await fixture.execute().manifest

        XCTAssertEqual(manifest.applicationVersion?.marketingVersion, "fixture-marketing")
        XCTAssertEqual(manifest.applicationVersion?.buildVersion, "fixture-build")
        XCTAssertEqual(manifest.schemaContractVersion, 31)
        XCTAssertEqual(manifest.manifestVersion, 11)
        XCTAssertEqual(manifest.pollingPolicyVersion, 21)
        XCTAssertEqual(manifest.modelInputManifestVersion, 41)
    }

    /// 端末名を含まないplatformだけをmanifestへ伝播します。
    ///
    /// 責務: runtime evidenceのacquisition platformをsemantic manifestへ固定します。
    func testPropagatesAcquisitionPlatform() async throws {
        let fixture = makeFixture(platform: .iPad)
        let platform = try await fixture.execute().manifest.acquisitionPlatform

        XCTAssertEqual(platform, .iPad)
    }

    /// ordered PID setの入力順を保持します。
    ///
    /// 責務: policyが確定したPID要求順を並べ替えずmanifestへ保存します。
    func testPreservesOrderedRequestedPIDSet() async throws {
        let fixture = makeFixture(orderedRequests: [secondRequest, firstRequest])
        let requests = try await fixture.execute().manifest.orderedRequestedPIDs?.requests

        XCTAssertEqual(requests, [secondRequest, firstRequest])
    }

    /// capability supportとcollection enabledを別軸で保持します。
    ///
    /// 責務: 非対応証拠と収集選択を相互変換せずPID snapshotへ伝播します。
    func testSeparatesCapabilitySupportFromCollectionSelection() async throws {
        let fixture = makeFixture(
            capabilities: [
                capability(firstRequest, support: .unsupported, enabled: true),
                capability(secondRequest, support: .supported, enabled: false)
            ]
        )
        let snapshots = try await fixture.execute().manifest.pidDefinitions

        XCTAssertEqual(snapshots[0].capabilitySupport, .unsupported)
        XCTAssertEqual(snapshots[0].isCollectionEnabled, true)
        XCTAssertEqual(snapshots[1].capabilitySupport, .supported)
        XCTAssertEqual(snapshots[1].isCollectionEnabled, false)
    }

    /// 判定不能capabilityをunsupportedへ変換しません。
    ///
    /// 責務: 明示されたindeterminate証拠を同じ状態のままmanifestへ固定します。
    func testPreservesIndeterminateCapability() async throws {
        let fixture = makeFixture(
            capabilities: [
                capability(firstRequest, support: .indeterminate, enabled: true),
                capability(secondRequest, support: .supported, enabled: true)
            ]
        )
        let support = try await fixture.execute().manifest.pidDefinitions.first?.capabilitySupport

        XCTAssertEqual(support, .indeterminate)
    }

    /// PID definitionのsemantic fieldを完全に伝播します。
    ///
    /// 責務: revision、byte数、formula identity、unit、rangeを取得時snapshotへ固定します。
    func testPropagatesCompletePIDDefinitionSnapshot() async throws {
        let fixture = makeFixture()
        let firstSnapshot = try await fixture.execute().manifest.pidDefinitions.first
        let snapshot = try XCTUnwrap(firstSnapshot)

        XCTAssertEqual(snapshot.definitionRevision, 7)
        XCTAssertEqual(snapshot.requiredByteCount, 2)
        XCTAssertEqual(snapshot.definitionIdentity?.canonicalizationVersion, 51)
        XCTAssertEqual(snapshot.definitionIdentity?.expression, "(A * 256 + B) / 4")
        XCTAssertEqual(snapshot.unit, "rpm")
        XCTAssertEqual(snapshot.validityRange?.minimum, 0)
        XCTAssertEqual(snapshot.validityRange?.maximum, 16_383.75)
    }

    /// requested PIDに対応するdefinition欠落を拒否します。
    ///
    /// 責務: definition snapshotを作れない要求集合からRaw開始許可を返さないことを確認します。
    func testRejectsMissingRequestedPIDDefinition() async {
        let missing = OBDPIDRequest(service: 1, pid: 14)
        let fixture = makeFixture(orderedRequests: [firstRequest, missing])
        let error = await capturedError(from: fixture)

        XCTAssertEqual(error, .manifest(.missingRequestedPIDDefinition))
        XCTAssertNil(fixture.acquisitionRepository.storedStartedAt)
    }

    /// capability一覧にないPIDを拒否します。
    ///
    /// 責務: capability欠落をunsupportedへ変換せずRaw開始前の明示失敗にします。
    func testRejectsMissingCapabilityEvidence() async {
        let fixture = makeFixture(
            capabilities: [capability(firstRequest, support: .supported, enabled: true)]
        )
        let error = await capturedError(from: fixture)

        XCTAssertEqual(error, .application(.capabilityEvidenceMissing))
        XCTAssertEqual(fixture.acquisitionRepository.saveStartCallCount, 0)
    }

    /// ordered PID setの重複を拒否します。
    ///
    /// 責務: 同じService/PIDを複数要求するmanifestを保存しないことを確認します。
    func testRejectsDuplicateRequestedPID() async {
        let fixture = makeFixture(orderedRequests: [firstRequest, firstRequest])
        let error = await capturedError(from: fixture)

        XCTAssertEqual(error, .orderedSet(.duplicateRequest))
        XCTAssertEqual(fixture.acquisitionRepository.saveStartCallCount, 0)
    }

    /// PID definition一覧の重複を拒否します。
    ///
    /// 責務: 同じService/PIDのdefinition snapshotを複数保存できないことを確認します。
    func testRejectsDuplicatePIDDefinition() async {
        let fixture = makeFixture(
            definitions: [engineSpeedDefinition, engineSpeedDefinition],
            capabilities: [capability(firstRequest, support: .supported, enabled: true)],
            orderedRequests: [firstRequest]
        )
        let error = await capturedError(from: fixture)

        XCTAssertEqual(error, .manifest(.duplicatePIDDefinition))
        XCTAssertEqual(fixture.acquisitionRepository.saveStartCallCount, 0)
    }

    /// capability一覧の重複を拒否します。
    ///
    /// 責務: 同じService/PIDの能力証拠を複数値から選ばず明示失敗にします。
    func testRejectsDuplicateCapabilityEvidence() async {
        let duplicated = capability(firstRequest, support: .supported, enabled: true)
        let fixture = makeFixture(
            definitions: [engineSpeedDefinition],
            capabilities: [duplicated, duplicated],
            orderedRequests: [firstRequest]
        )
        let error = await capturedError(from: fixture)

        XCTAssertEqual(error, .application(.duplicateCapabilityEvidence))
        XCTAssertEqual(fixture.acquisitionRepository.saveStartCallCount, 0)
    }

    /// repository duplicateをcanonical exact retryとして許可します。
    ///
    /// 責務: 同一sessionへの同一manifest再保存が保存済みmanifestのRaw開始許可を返すことを確認します。
    func testCanonicalRepositoryDuplicateReturnsPermission() async throws {
        let fixture = makeFixture()
        let original = try await fixture.execute()
        let retry = try await fixture.execute()

        XCTAssertEqual(retry, original)
        XCTAssertEqual(fixture.acquisitionRepository.saveStartCallCount, 2)
        XCTAssertEqual(fixture.acquisitionRepository.storedStartedAt, fixture.startedAt)
    }

    /// repository conflictを成功へ変換せず伝播します。
    ///
    /// 責務: 同一sessionの異内容manifest競合をRaw開始許可として扱わないことを確認します。
    func testPropagatesRepositoryConflict() async {
        let fixture = makeFixture(repositoryError: .conflict)
        let error = await capturedError(from: fixture)

        XCTAssertEqual(error, .repository(.conflict))
        XCTAssertFalse(fixture.acquisitionRepository.hasObservablePartialSuccess)
    }

    /// repository unavailableを成功へ変換せず伝播します。
    ///
    /// 責務: manifest保存先failureを空データまたは通常接続成功へ変換しないことを確認します。
    func testPropagatesRepositoryUnavailable() async {
        let fixture = makeFixture(repositoryError: .unavailable)
        let error = await capturedError(from: fixture)

        XCTAssertEqual(error, .repository(.unavailable))
        XCTAssertFalse(fixture.acquisitionRepository.hasObservablePartialSuccess)
    }

    /// 原子保存失敗時に片方だけの成功もRaw許可も生成しません。
    ///
    /// 責務: repository失敗をmanifestまたは開始境界だけの観測可能な成功へ変換しないことを確認します。
    func testRepositoryFailureDoesNotExposePartialSuccessOrAllowRawAcquisition() async {
        let fixture = makeFixture(repositoryError: .unavailable)

        _ = await capturedError(from: fixture)

        XCTAssertFalse(fixture.acquisitionRepository.hasObservablePartialSuccess)
    }

    /// evidence取得中に世代が変わった結果を保存しません。
    ///
    /// 責務: 古いpolling世代のasync runtime結果を新しいsession取得へ混入させないことを確認します。
    func testDiscardsResultFromStaleGeneration() async throws {
        let port = SuspendedAcquisitionEvidencePort(evidence: runtimeEvidence())
        let fixture = makeFixture(evidencePort: port)
        await fixture.useCase.activate(generation: fixture.input.generation)
        let task = Task { try await fixture.useCase.execute(fixture.input) }
        while !(await port.isWaiting) { await Task.yield() }

        await fixture.useCase.activate(generation: fixture.input.generation + 1)
        await port.resume()

        await assertInactiveGeneration(task)
        XCTAssertEqual(fixture.acquisitionRepository.saveStartCallCount, 0)
        XCTAssertFalse(fixture.acquisitionRepository.hasObservablePartialSuccess)
    }

    /// evidence取得中のcancel後に結果を保存しません。
    ///
    /// 責務: cancel済みpolling世代のasync runtime結果からmanifestまたはRaw開始許可を作らないことを確認します。
    func testDiscardsResultAfterCancellation() async throws {
        let port = SuspendedAcquisitionEvidencePort(evidence: runtimeEvidence())
        let fixture = makeFixture(evidencePort: port)
        await fixture.useCase.activate(generation: fixture.input.generation)
        let task = Task { try await fixture.useCase.execute(fixture.input) }
        while !(await port.isWaiting) { await Task.yield() }

        await fixture.useCase.cancel(generation: fixture.input.generation)
        await port.resume()

        await assertInactiveGeneration(task)
        XCTAssertEqual(fixture.acquisitionRepository.saveStartCallCount, 0)
    }

    /// retryが既存manifestを更新しません。
    ///
    /// 責務: 初回保存後の再実行が元manifestと開始境界を維持して同じ許可を返すことを確認します。
    func testRetryDoesNotUpdateExistingManifest() async throws {
        let fixture = makeFixture()
        let original = try await fixture.execute()
        let retry = try await fixture.execute()

        XCTAssertEqual(retry, original)
        XCTAssertEqual(fixture.acquisitionRepository.storedManifest, original.manifest)
        XCTAssertEqual(fixture.clock.callCount, 1)
        XCTAssertEqual(fixture.acquisitionRepository.storedStartedAt, fixture.startedAt)
    }

    /// stale generation taskの結果を検証します。
    ///
    /// 責務: 非同期taskがinactive generationだけを返すことを確認します。
    /// - Parameter task: staleまたはcancel済みにしたmanifest作成task。
    private func assertInactiveGeneration(
        _ task: Task<ConnectionSessionRawAcquisitionPermission, Error>
    ) async {
        do {
            _ = try await task.value
            XCTFail("inactive generation must not return permission")
        } catch {
            XCTAssertEqual(
                error as? CreateConnectionSessionAcquisitionManifestError,
                .inactiveGeneration
            )
        }
    }

    /// fixture実行時の型付きerrorを取得します。
    ///
    /// 責務: Raw許可を期待しないtestで排他的な失敗種別を比較可能にします。
    /// - Parameter fixture: 実行するmanifest作成fixture。
    /// - Returns: use caseが投げた分類済みtest error。
    private func capturedError(from fixture: UseCaseFixture) async -> CapturedError? {
        do {
            _ = try await fixture.execute()
            return nil
        } catch let error as CreateConnectionSessionAcquisitionManifestError {
            return .application(error)
        } catch let error as ConnectionSessionAcquisitionManifestError {
            return .manifest(error)
        } catch let error as OrderedAcquisitionPIDSetError {
            return .orderedSet(error)
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            return .repository(error)
        } catch {
            return .unexpected
        }
    }

    /// manifest作成testの依存と入力を生成します。
    ///
    /// 責務: 実識別情報とRaw payloadを含まない決定的なApplication fixtureを返します。
    /// - Parameters:
    ///   - platform: runtime evidenceへ設定するplatform。
    ///   - definitions: 取得開始時点のPID定義一覧。
    ///   - capabilities: PID能力と収集選択。省略時は2件のsupported入力。
    ///   - orderedRequests: manifestへ保持するPID要求順。
    ///   - repositoryError: 原子repositoryが返す明示失敗。
    ///   - evidencePort: runtime evidence port。省略時は即時成功fixture。
    /// - Returns: 初期世代を有効化して実行できるuse case fixture。
    private func makeFixture(
        platform: ConnectionSessionAcquisitionPlatform = .macOS,
        definitions: [OBDPIDDefinition]? = nil,
        capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput]? = nil,
        orderedRequests: [OBDPIDRequest]? = nil,
        repositoryError: ConnectionSessionAcquisitionRepositoryError? = nil,
        evidencePort: (any ConnectionSessionAcquisitionEvidencePort)? = nil
    ) -> UseCaseFixture {
        let acquisitionRepository = AcquisitionRepositorySpy(saveError: repositoryError)
        let clock = AdvancingClock(firstDate: Date(timeIntervalSinceReferenceDate: 500))
        let input = CreateConnectionSessionAcquisitionManifestInput(
            sessionID: syntheticSessionID,
            generation: 101,
            manifestVersion: 11,
            pollingPolicyVersion: 21,
            modelInputManifestVersion: 41,
            formulaCanonicalizationVersion: 51,
            pidDefinitions: definitions ?? [engineSpeedDefinition, vehicleSpeedDefinition],
            pidCapabilities: capabilities ?? [
                capability(firstRequest, support: .supported, enabled: true),
                capability(secondRequest, support: .supported, enabled: true)
            ],
            orderedRequestedPIDs: orderedRequests ?? [firstRequest, secondRequest]
        )
        let port = evidencePort ?? FixedAcquisitionEvidencePort(
            evidence: runtimeEvidence(platform: platform)
        )
        let useCase = CreateConnectionSessionAcquisitionManifestUseCase(
            acquisitionRepository: acquisitionRepository,
            evidencePort: port,
            now: clock.now
        )
        return UseCaseFixture(
            useCase: useCase,
            input: input,
            acquisitionRepository: acquisitionRepository,
            clock: clock,
            startedAt: Date(timeIntervalSinceReferenceDate: 500)
        )
    }

    /// runtime authorityのsynthetic evidenceを生成します。
    ///
    /// 責務: 実Production versionや端末名を含まないmanifest runtime fixtureを返します。
    /// - Parameter platform: fixtureへ設定するacquisition platform。
    /// - Returns: app/build/schema/platformのsynthetic evidence。
    private func runtimeEvidence(
        platform: ConnectionSessionAcquisitionPlatform = .macOS
    ) -> ConnectionSessionAcquisitionRuntimeEvidence {
        ConnectionSessionAcquisitionRuntimeEvidence(
            applicationVersion: try! AcquisitionApplicationVersion(
                marketingVersion: "fixture-marketing",
                buildVersion: "fixture-build"
            ),
            schemaContractVersion: 31,
            acquisitionPlatform: platform
        )
    }

    /// PID capability fixtureを生成します。
    ///
    /// 責務: 対応状態と収集選択を独立に指定したsynthetic入力を返します。
    /// - Parameters:
    ///   - request: synthetic Service/PID。
    ///   - support: 明示capability状態。
    ///   - enabled: 収集選択。
    /// - Returns: manifest作成用capability入力。
    private func capability(
        _ request: OBDPIDRequest,
        support: AcquisitionPIDCapabilitySupport,
        enabled: Bool
    ) -> ConnectionSessionAcquisitionPIDCapabilityInput {
        ConnectionSessionAcquisitionPIDCapabilityInput(
            request: request,
            support: support,
            isCollectionEnabled: enabled
        )
    }

    /// engine speed用synthetic PID定義です。
    private var engineSpeedDefinition: OBDPIDDefinition {
        makeDefinition(
            request: firstRequest,
            requiredByteCount: 2,
            formula: "(A * 256 + B) / 4",
            unit: "rpm",
            minimum: 0,
            maximum: 16_383.75,
            revision: 7
        )
    }

    /// vehicle speed用synthetic PID定義です。
    private var vehicleSpeedDefinition: OBDPIDDefinition {
        makeDefinition(
            request: secondRequest,
            requiredByteCount: 1,
            formula: "A",
            unit: "km/h",
            minimum: 0,
            maximum: 255,
            revision: 8
        )
    }

    /// synthetic PID定義を生成します。
    ///
    /// 責務: manifest mapping testへ実車固有値を含まない完全なPID定義を返します。
    /// - Parameters:
    ///   - request: synthetic Service/PID。
    ///   - requiredByteCount: formulaが必要とするbyte数。
    ///   - formula: synthetic制限付き式。
    ///   - unit: synthetic semantic unit。
    ///   - minimum: inclusive下限。
    ///   - maximum: inclusive上限。
    ///   - revision: synthetic definition revision。
    /// - Returns: manifest snapshotへ変換するPID定義。
    private func makeDefinition(
        request: OBDPIDRequest,
        requiredByteCount: Int,
        formula: String,
        unit: String,
        minimum: Double,
        maximum: Double,
        revision: Int
    ) -> OBDPIDDefinition {
        OBDPIDDefinition(
            service: request.service,
            pid: request.pid,
            nameKey: "fixture.pid.name",
            requiredByteCount: requiredByteCount,
            formula: formula,
            unit: unit,
            minimumValue: minimum,
            maximumValue: maximum,
            sourceURI: "https://fixture.invalid/pid",
            revision: revision
        )
    }

    /// 最初のsynthetic PID要求です。
    private var firstRequest: OBDPIDRequest { OBDPIDRequest(service: 1, pid: 12) }
    /// 2番目のsynthetic PID要求です。
    private var secondRequest: OBDPIDRequest { OBDPIDRequest(service: 1, pid: 13) }
    /// 実sessionと無関係な固定session IDです。
    private var syntheticSessionID: ConnectionSessionID {
        ConnectionSessionID(
            rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 90))
        )
    }
}

/// use case実行に必要なtest依存を保持します。
private struct UseCaseFixture {
    /// 検証対象use caseです。
    let useCase: CreateConnectionSessionAcquisitionManifestUseCase
    /// 実行する完全入力です。
    let input: CreateConnectionSessionAcquisitionManifestInput
    /// manifestと開始境界の原子保存spyです。
    let acquisitionRepository: AcquisitionRepositorySpy
    /// retry間で異なる時刻を返し得るclock spyです。
    let clock: AdvancingClock
    /// 開始eventへ記録する固定時刻です。
    let startedAt: Date

    /// 初期世代を有効化してuse caseを実行します。
    ///
    /// 責務: fixture入力と同じpolling世代でmanifest作成を開始します。
    /// - Returns: 保存成功後のRaw開始許可。
    /// - Throws: use caseが伝播する入力、世代、port、repository error。
    func execute() async throws -> ConnectionSessionRawAcquisitionPermission {
        await useCase.activate(generation: input.generation)
        return try await useCase.execute(input)
    }
}

/// 呼出しごとに異なる時刻を返すthread-safeなtest clockです。
private final class AdvancingClock: @unchecked Sendable {
    /// clock状態を保護するlockです。
    private let lock = NSLock()
    /// 最初の呼出しで返す時刻です。
    private let firstDate: Date
    /// 現在までの呼出し回数です。
    private var storedCallCount = 0

    /// clock spyを生成します。
    ///
    /// 責務: 最初に返すsynthetic時刻を固定します。
    /// - Parameter firstDate: 最初の呼出しで返す時刻。
    init(firstDate: Date) {
        self.firstDate = firstDate
    }

    /// 現在までの時刻要求回数です。
    var callCount: Int {
        lock.withLock { storedCallCount }
    }

    /// 呼出し回数に応じたsynthetic時刻を返します。
    ///
    /// 責務: retryがclockを再採番した場合に異なる値となる決定的時刻を供給します。
    /// - Returns: 最初の時刻へ呼出し回数分の秒を加えた値。
    func now() -> Date {
        lock.withLock {
            defer { storedCallCount += 1 }
            return firstDate.addingTimeInterval(TimeInterval(storedCallCount))
        }
    }
}

/// test比較用に複数error型を排他的に包みます。
private enum CapturedError: Equatable {
    /// Application入力または世代errorです。
    case application(CreateConnectionSessionAcquisitionManifestError)
    /// Domain manifest生成errorです。
    case manifest(ConnectionSessionAcquisitionManifestError)
    /// ordered set生成errorです。
    case orderedSet(OrderedAcquisitionPIDSetError)
    /// manifest repository errorです。
    case repository(ConnectionSessionAcquisitionRepositoryError)
    /// testが分類していないerrorです。
    case unexpected
}

/// runtime evidenceを即時返すport fixtureです。
private struct FixedAcquisitionEvidencePort: ConnectionSessionAcquisitionEvidencePort {
    /// 返却するsynthetic runtime evidenceです。
    let storedEvidence: ConnectionSessionAcquisitionRuntimeEvidence

    /// 即時成功portを生成します。
    ///
    /// 責務: 指定runtime evidenceを変更せず保持します。
    /// - Parameter evidence: 返却するsynthetic runtime evidence。
    init(evidence: ConnectionSessionAcquisitionRuntimeEvidence) {
        storedEvidence = evidence
    }

    /// 保存済みruntime evidenceを返します。
    ///
    /// 責務: manifest作成testへ決定的なruntime evidenceを供給します。
    /// - Returns: 初期化時に保持したruntime evidence。
    func evidence() async throws -> ConnectionSessionAcquisitionRuntimeEvidence {
        storedEvidence
    }
}

/// runtime取得をtestが再開するまで保留するport fixtureです。
private actor SuspendedAcquisitionEvidencePort: ConnectionSessionAcquisitionEvidencePort {
    /// 再開時に返すsynthetic runtime evidenceです。
    private let storedEvidence: ConnectionSessionAcquisitionRuntimeEvidence
    /// 保留中のruntime要求です。
    private var continuation: CheckedContinuation<ConnectionSessionAcquisitionRuntimeEvidence, Error>?

    /// 保留portを生成します。
    ///
    /// 責務: 後から返すruntime evidenceを保持します。
    /// - Parameter evidence: 再開時に返すsynthetic runtime evidence。
    init(evidence: ConnectionSessionAcquisitionRuntimeEvidence) {
        storedEvidence = evidence
    }

    /// runtime要求が保留状態に入ったかを示します。
    var isWaiting: Bool { continuation != nil }

    /// testが再開するまでruntime要求を保留します。
    ///
    /// 責務: polling世代変更を挟めるasync evidence取得境界を再現します。
    /// - Returns: `resume()` 後のsynthetic runtime evidence。
    func evidence() async throws -> ConnectionSessionAcquisitionRuntimeEvidence {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    /// 保留中のruntime要求を成功で再開します。
    ///
    /// 責務: 1件の保留要求へ保持済みruntime evidenceを返します。
    func resume() {
        continuation?.resume(returning: storedEvidence)
        continuation = nil
    }
}

/// manifestとRaw境界の原子保存呼出しと保存値を記録します。
private final class AcquisitionRepositorySpy:
    ConnectionSessionAcquisitionRepository,
    @unchecked Sendable {
    /// testから注入された保存失敗です。
    private let saveError: ConnectionSessionAcquisitionRepositoryError?
    /// 保存済みmanifestです。
    private(set) var storedManifest: ConnectionSessionAcquisitionManifest?
    /// 保存済みRaw開始境界時刻です。
    private(set) var storedStartedAt: Date?
    /// 保存済みRaw終了境界です。
    private(set) var storedEnd: AcquisitionRawBoundaryEvidence?
    /// 原子保存呼出し回数です。
    private(set) var saveStartCallCount = 0
    /// manifestと開始境界の片方だけが観測可能かを示します。
    var hasObservablePartialSuccess: Bool {
        (storedManifest == nil) != (storedStartedAt == nil)
    }

    /// 原子repository spyを生成します。
    ///
    /// 責務: 保存時に返す任意errorを固定します。
    /// - Parameter saveError: 初回保存でも返すrepository error。
    init(saveError: ConnectionSessionAcquisitionRepositoryError?) {
        self.saveError = saveError
    }

    /// manifestとRaw開始境界を一度だけ同時に記録します。
    ///
    /// 責務: 部分状態を公開せずduplicate、conflict、unavailableをfixtureとして再現します。
    /// - Parameters:
    ///   - manifest: 保存対象manifest。
    ///   - startedAt: 保存対象の開始境界時刻。
    ///   - sessionID: synthetic session識別子。
    /// - Throws: 注入error、同じ組なら `duplicate`、異なる組なら `conflict`。
    func saveStartOnce(
        manifest: ConnectionSessionAcquisitionManifest,
        startedAt: Date,
        for sessionID: ConnectionSessionID
    ) throws {
        saveStartCallCount += 1
        if let saveError { throw saveError }
        if let storedManifest, let storedStartedAt {
            throw storedManifest == manifest && storedStartedAt == startedAt
                ? ConnectionSessionAcquisitionRepositoryError.duplicate
                : ConnectionSessionAcquisitionRepositoryError.conflict
        }
        storedManifest = manifest
        storedStartedAt = startedAt
    }

    /// Raw終了境界を一度だけ追記します。
    ///
    /// 責務: 開始済みfixtureへ終了eventを既存値の更新なしで追記します。
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
        guard let storedStartedAt else {
            throw ConnectionSessionAcquisitionRepositoryError.startEvidenceMissing
        }
        let evidence = AcquisitionRawBoundaryEvidence.ended(at: endedAt, reason: reason)
        if let storedEnd {
            throw storedEnd == evidence
                ? ConnectionSessionAcquisitionRepositoryError.duplicate
                : ConnectionSessionAcquisitionRepositoryError.conflict
        }
        guard endedAt >= storedStartedAt else {
            throw ConnectionSessionAcquisitionRepositoryError.endBeforeStart
        }
        storedEnd = evidence
    }

    /// 保存済みmanifestを返します。
    ///
    /// 責務: spyが保持するmanifestを変更せず読み取ります。
    /// - Parameter sessionID: synthetic session識別子。
    /// - Returns: 保存済みmanifest。
    /// - Throws: 未保存の場合は `notFound`。
    func manifest(for sessionID: ConnectionSessionID) throws -> ConnectionSessionAcquisitionManifest {
        guard let storedManifest else {
            throw ConnectionSessionAcquisitionRepositoryError.notFound
        }
        return storedManifest
    }

    /// 保存済み境界eventを返します。
    ///
    /// 責務: spyが記録した開始と終了eventを追記順のまま読み取ります。
    /// - Parameter sessionID: synthetic session識別子。
    /// - Returns: 保存済み境界event列。
    func boundaryEvidence(for sessionID: ConnectionSessionID) throws -> [AcquisitionRawBoundaryEvidence] {
        var evidence: [AcquisitionRawBoundaryEvidence] = []
        if let storedStartedAt {
            evidence.append(.started(at: storedStartedAt))
        }
        if let storedEnd {
            evidence.append(storedEnd)
        }
        return evidence
    }
}
