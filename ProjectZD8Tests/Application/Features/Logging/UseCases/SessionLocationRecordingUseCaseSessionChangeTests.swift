import XCTest
@testable import ProjectZD8

/// `SessionLocationRecordingUseCase` が現在のセッションの変化(同じ ID・nil・別の ID)に応じて購読と事象を扱うことを検証します。
@MainActor
final class SessionLocationRecordingUseCaseSessionChangeTests: XCTestCase {
    /// 現在のテストの土台です(後始末に使います)。
    private var harness: SessionLocationRecordingUseCaseHarness?

    /// 購読と記録のタスクを後始末します。
    ///
    /// 責務: セッションを外し、残った流れを終えます。
    override func tearDown() async throws {
        harness?.tearDown()
        harness = nil
        try await super.tearDown()
    }

    /// 設定オン・常に許可・前面でセッションを始め、位置の保存が動くところまで進めます。
    ///
    /// 責務: 記録中の状態(事象 `recording`、購読1件、位置1点の保存)を作って返します。
    /// - Returns: 土台と記録中のセッション。
    /// - Throws: 位置を作れない場合のテスト失敗。
    private func startRecording() async throws -> (SessionLocationRecordingUseCaseHarness, ConnectionSessionID) {
        let made = SessionLocationRecordingUseCaseHarness(
            isRecordingEnabled: true, permission: SessionLocationRecordingUseCaseHarness.permission(.always), isForeground: true
        )
        harness = made
        let sessionID = ConnectionSessionID()
        made.useCase.activeSessionDidChange(sessionID)
        await made.waitForEventKinds([.recording], for: sessionID)
        await made.waitForSubscriptions(subscribed: 1, terminated: 0)
        try await made.yieldFixAndWaitSaved(index: 1, to: sessionID)
        return (made, sessionID)
    }

    /// 同じ ID を続けて渡しても、購読し直さず事象も増えません。
    ///
    /// 責務: 重複した通知が無視され、購読と事象がそのままであることを確認します。
    func testSameSessionIDTwiceDoesNothing() async throws {
        let (harness, sessionID) = try await startRecording()
        harness.useCase.activeSessionDidChange(sessionID)
        harness.useCase.activeSessionDidChange(sessionID)
        await harness.settle()
        XCTAssertEqual(harness.subscription.subscribeCallCount, 1)
        XCTAssertEqual(harness.subscription.terminationCount, 0)
        XCTAssertEqual(harness.repository.storedEventKinds(for: sessionID), [.recording])
        try await harness.yieldFixAndWaitSaved(index: 2, to: sessionID)
    }

    /// nil で購読を取消し、その後の許可・前面・設定の変化では事象を書かず購読もしません。
    ///
    /// 責務: セッションが無い間は記録も事象の追記も起きないことを確認します。
    func testNilSessionCancelsAndIgnoresLaterChanges() async throws {
        let (harness, sessionID) = try await startRecording()
        harness.useCase.activeSessionDidChange(nil)
        await harness.waitForSubscriptions(subscribed: 1, terminated: 1)

        harness.useCase.permissionDidChange(SessionLocationRecordingUseCaseHarness.permission(.denied))
        harness.useCase.foregroundDidChange(isForeground: false)
        harness.useCase.recordingPreferenceDidChange(isEnabled: false)
        harness.useCase.recordingPreferenceDidChange(isEnabled: true)
        harness.useCase.permissionDidChange(SessionLocationRecordingUseCaseHarness.permission(.always))
        harness.useCase.foregroundDidChange(isForeground: true)
        await harness.settle()
        XCTAssertEqual(harness.repository.storedEventKinds(for: sessionID), [.recording])
        XCTAssertEqual(harness.subscription.subscribeCallCount, 1)
        XCTAssertEqual(harness.diagnostics.eventFailures, [])
    }

    /// nil の後に同じ ID が戻ると再評価し、事象をもう1行書いて購読し直します。
    ///
    /// 責務: 続行での復帰が新しい開始として扱われ、同じセッションへ位置が保存され続けることを確認します。
    func testSameSessionReturningAfterNilIsReevaluated() async throws {
        let (harness, sessionID) = try await startRecording()
        harness.useCase.activeSessionDidChange(nil)
        await harness.waitForSubscriptions(subscribed: 1, terminated: 1)

        harness.useCase.activeSessionDidChange(sessionID)
        await harness.waitForEventKinds([.recording, .recording], for: sessionID)
        await harness.waitForSubscriptions(subscribed: 2, terminated: 1)
        try await harness.yieldFixAndWaitSaved(index: 2, to: sessionID)
        XCTAssertEqual(harness.repository.storedFixes(for: sessionID).count, 2)
    }

    /// 別の ID に替わると前の購読を取消し、新しい ID へ事象を書き、以降の位置を新しい ID へ保存します。
    ///
    /// 責務: セッションの切替で保存先と事象の書き先が新しいセッションへ移ることを確認します。
    func testSwitchingSessionMovesRecordingToNewSession() async throws {
        let (harness, firstSession) = try await startRecording()
        let firstFixes = harness.repository.storedFixes(for: firstSession)
        let secondSession = ConnectionSessionID()
        harness.useCase.activeSessionDidChange(secondSession)

        await harness.waitForSubscriptions(subscribed: 2, terminated: 1)
        await harness.waitForEventKinds([.recording], for: secondSession)
        let moved = try await harness.yieldFixAndWaitSaved(index: 2, to: secondSession)
        XCTAssertEqual(harness.repository.storedFixes(for: secondSession), [moved])
        XCTAssertEqual(harness.repository.storedFixes(for: firstSession), firstFixes)
        XCTAssertEqual(harness.repository.storedEventKinds(for: firstSession), [.recording])
    }

    /// 記録していないセッションから別の ID に替わっても、新しい ID の判定で事象を書きます。
    ///
    /// 責務: 設定オフのセッションの切替で、新しい ID にも `disabledBySetting` が1行書かれることを確認します。
    func testSwitchingSessionWhileDisabledWritesEventForNewSession() async {
        let made = SessionLocationRecordingUseCaseHarness(
            isRecordingEnabled: false, permission: SessionLocationRecordingUseCaseHarness.permission(.always), isForeground: true
        )
        harness = made
        let firstSession = ConnectionSessionID()
        let secondSession = ConnectionSessionID()
        made.useCase.activeSessionDidChange(firstSession)
        await made.waitForEventKinds([.disabledBySetting], for: firstSession)
        made.useCase.activeSessionDidChange(secondSession)
        await made.waitForEventKinds([.disabledBySetting], for: secondSession)
        XCTAssertEqual(made.repository.storedEventKinds(for: firstSession), [.disabledBySetting])
        await made.settle()
        XCTAssertEqual(made.subscription.subscribeCallCount, 0)
    }
}
