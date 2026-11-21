import XCTest
@testable import ProjectZD8

/// `ConnectionSessionLocationRecorder` が位置を保存し、取得可否の変化を報告し、終わり方に応じて戻ることを検証します。
@MainActor
final class ConnectionSessionLocationRecorderTests: XCTestCase {
    /// 位置の Repository の spy です。
    private var repository: ConnectionSessionLocationRepositorySpy!
    /// 診断の spy です。
    private var diagnostics: SessionLocationRecordingDiagnosticsSpy!
    /// 取得可否の報告と戻りの記録です。
    private var log: ConnectionSessionLocationRecorderReportLog!
    /// 記録対象の流れへ流す口です。
    private var continuation: AsyncStream<LocationUpdateEvent>.Continuation?
    /// `record` を実行するタスクです。
    private var recordingTask: Task<Void, Never>?
    /// 記録先の接続セッションです。
    private var sessionID: ConnectionSessionID!

    /// 新しい流れで記録を始めます。
    ///
    /// 責務: spy と流れを用意し、別タスクで `record` を実行して報告と戻りを記録します。
    private func startRecording() {
        let repository = ConnectionSessionLocationRepositorySpy()
        let diagnostics = SessionLocationRecordingDiagnosticsSpy()
        let log = ConnectionSessionLocationRecorderReportLog()
        let sessionID = ConnectionSessionID()
        let (stream, continuation) = AsyncStream.makeStream(of: LocationUpdateEvent.self)
        let recorder = ConnectionSessionLocationRecorder(repository: repository, diagnostics: diagnostics)
        self.repository = repository
        self.diagnostics = diagnostics
        self.log = log
        self.sessionID = sessionID
        self.continuation = continuation
        recordingTask = Task { @MainActor in
            await recorder.record(stream, sessionID: sessionID, availabilityDidChange: { log.reports.append($0) })
            log.didReturn = true
        }
    }

    /// 流れとタスクを後始末します。
    ///
    /// 責務: 実装が戻らなかった場合でも、流れを終えてタスクを取消します。
    override func tearDown() async throws {
        continuation?.finish()
        recordingTask?.cancel()
        continuation = nil
        recordingTask = nil
        try await super.tearDown()
    }

    /// 受けた順に位置を指定したセッションへ保存し、位置だけが続く間は何も報告しません。
    ///
    /// 責務: 3点が同順で保存され、取得可否の報告が無いことを確認します。
    func testSavesFixesInReceivedOrderWithoutReporting() async throws {
        startRecording()
        let fixes = try (1...3).map { try ConnectionSessionLocationTestValues.fix(index: $0) }
        fixes.forEach { continuation?.yield(.fix($0)) }
        await LocationRecordingBoundedWaiter.waitUntil("3点が保存される") { repository.storedFixes(for: sessionID) == fixes }
        await LocationRecordingBoundedWaiter.settle()
        XCTAssertEqual(log.reports, [])
        XCTAssertEqual(diagnostics.sampleFailures, [])
        XCTAssertFalse(log.didReturn)
    }

    /// 取得不可で false、その後の位置で true を報告し、同じ値は続けて報告しません。
    ///
    /// 責務: 取得不可2回で false が1回、位置2点で true が1回だけ報告され、取得不可は保存されないことを確認します。
    func testReportsAvailabilityChangesWithoutRepeats() async throws {
        startRecording()
        continuation?.yield(.unavailable(.temporarilyUnavailable))
        await LocationRecordingBoundedWaiter.waitUntil("取得不可が報告される") { log.reports == [false] }
        continuation?.yield(.unavailable(.failed))
        let first = try ConnectionSessionLocationTestValues.fix(index: 1)
        continuation?.yield(.fix(first))
        await LocationRecordingBoundedWaiter.waitUntil("位置が保存される") { repository.storedFixes(for: sessionID) == [first] }
        await LocationRecordingBoundedWaiter.waitUntil("復帰が報告される") { log.reports == [false, true] }

        let second = try ConnectionSessionLocationTestValues.fix(index: 2)
        continuation?.yield(.fix(second))
        await LocationRecordingBoundedWaiter.waitUntil("2点目が保存される") { repository.storedFixes(for: sessionID) == [first, second] }
        await LocationRecordingBoundedWaiter.settle()
        XCTAssertEqual(log.reports, [false, true])
    }

    /// 位置の保存に失敗すると診断へセッション付きで残し、以降の位置も保存を試み続けます。
    ///
    /// 責務: 失敗2回が診断に2件残り、失敗を解いた後の位置が保存されることを確認します。
    func testSampleStorageFailureIsDiagnosedAndRecordingContinues() async throws {
        startRecording()
        repository.setFailsAppendSample(true)
        continuation?.yield(.fix(try ConnectionSessionLocationTestValues.fix(index: 1)))
        await LocationRecordingBoundedWaiter.waitUntil("1回目の失敗が残る") { diagnostics.sampleFailures == [sessionID] }
        continuation?.yield(.fix(try ConnectionSessionLocationTestValues.fix(index: 2)))
        await LocationRecordingBoundedWaiter.waitUntil("2回目の失敗が残る") { diagnostics.sampleFailures == [sessionID, sessionID] }

        repository.setFailsAppendSample(false)
        let recovered = try ConnectionSessionLocationTestValues.fix(index: 3)
        continuation?.yield(.fix(recovered))
        await LocationRecordingBoundedWaiter.waitUntil("失敗の後も保存される") { repository.storedFixes(for: sessionID) == [recovered] }
        XCTAssertEqual(repository.appendSampleAttemptCount, 3)
        XCTAssertEqual(diagnostics.sampleFailures, [sessionID, sessionID])
        XCTAssertFalse(log.didReturn)
    }

    /// 取消されずに流れが終わると取得不可を報告して戻ります。
    ///
    /// 責務: 位置の後に流れが自然終了すると false が1回報告され、`record` が戻ることを確認します。
    func testNaturalEndReportsUnavailableAndReturns() async throws {
        startRecording()
        let fix = try ConnectionSessionLocationTestValues.fix(index: 1)
        continuation?.yield(.fix(fix))
        continuation?.finish()
        await LocationRecordingBoundedWaiter.waitUntil("record が戻る") { log.didReturn }
        XCTAssertEqual(log.reports, [false])
        XCTAssertEqual(repository.storedFixes(for: sessionID), [fix])
    }

    /// 何も届かずに流れが終わっても取得不可を報告して戻ります。
    ///
    /// 責務: 空の流れの自然終了で false が1回報告され、`record` が戻ることを確認します。
    func testNaturalEndOfEmptyStreamReportsUnavailable() async {
        startRecording()
        continuation?.finish()
        await LocationRecordingBoundedWaiter.waitUntil("record が戻る") { log.didReturn }
        XCTAssertEqual(log.reports, [false])
    }

    /// 既に取得不可を報告した後の自然終了では、false を重ねて報告しません。
    ///
    /// 責務: 取得不可の直後に流れが終わっても報告が false の1回だけであることを確認します。
    func testNaturalEndAfterUnavailableDoesNotRepeatReport() async {
        startRecording()
        continuation?.yield(.unavailable(.temporarilyUnavailable))
        await LocationRecordingBoundedWaiter.waitUntil("取得不可が報告される") { log.reports == [false] }
        continuation?.finish()
        await LocationRecordingBoundedWaiter.waitUntil("record が戻る") { log.didReturn }
        XCTAssertEqual(log.reports, [false])
    }

    /// タスクを取消すと戻り、取消による終了では取得不可を報告しません。
    ///
    /// 責務: 位置だけを受けた後の取消で、報告が無いまま `record` が戻ることを確認します。
    func testCancellationReturnsWithoutReportingUnavailable() async throws {
        startRecording()
        let fix = try ConnectionSessionLocationTestValues.fix(index: 1)
        continuation?.yield(.fix(fix))
        await LocationRecordingBoundedWaiter.waitUntil("位置が保存される") { repository.storedFixes(for: sessionID) == [fix] }
        recordingTask?.cancel()
        await LocationRecordingBoundedWaiter.waitUntil("record が戻る") { log.didReturn }
        XCTAssertEqual(log.reports, [])
    }

    /// 取得不可から復帰した後の取消でも、取得不可を報告しません。
    ///
    /// 責務: 報告が false・true の後に取消しても、それ以上の報告が増えずに戻ることを確認します。
    func testCancellationAfterRecoveryDoesNotReportAgain() async throws {
        startRecording()
        continuation?.yield(.unavailable(.failed))
        continuation?.yield(.fix(try ConnectionSessionLocationTestValues.fix(index: 1)))
        await LocationRecordingBoundedWaiter.waitUntil("取得不可と復帰が報告される") { log.reports == [false, true] }
        recordingTask?.cancel()
        await LocationRecordingBoundedWaiter.waitUntil("record が戻る") { log.didReturn }
        XCTAssertEqual(log.reports, [false, true])
    }
}

/// 記録の受け手から届いた取得可否の報告と、`record` が戻ったかどうかを持つ記録です。
@MainActor
private final class ConnectionSessionLocationRecorderReportLog {
    /// 取得可否の報告です(受信順)。
    var reports: [Bool] = []
    /// `record` が戻った場合は `true` です。
    var didReturn = false
}
