import XCTest
@testable import ProjectZD8

/// `SessionLocationRecordingUseCase` が記録中の設定・許可・取得可否の変化で購読と事象を更新することを検証します。
@MainActor
final class SessionLocationRecordingUseCaseTransitionTests: XCTestCase {
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

    /// 記録中に設定をオフにすると購読を取消し、`disabledBySetting` を書きます。
    ///
    /// 責務: 途中のオフで取得が止まり、事象が追記されることを確認します。
    func testTurningPreferenceOffCancelsSubscription() async throws {
        let (harness, sessionID) = try await startRecording()
        harness.useCase.recordingPreferenceDidChange(isEnabled: false)

        await harness.waitForSubscriptions(subscribed: 1, terminated: 1)
        await harness.waitForEventKinds([.recording, .disabledBySetting], for: sessionID)
    }

    /// 記録中に許可が取得できない段階へ変わると購読を取消し、段階に応じた事象を書きます。
    ///
    /// 責務: 拒否・未確定・制限のそれぞれで取得が止まり、対応する事象が追記されることを確認します。
    func testLosingPermissionCancelsSubscription() async throws {
        let cases: [(LocationAuthorizationLevel, ConnectionSessionLocationEventKind)] = [
            (.denied, .authorizationDenied),
            (.notDetermined, .authorizationNotDetermined),
            (.restricted, .authorizationRestricted)
        ]
        for (level, expectedKind) in cases {
            let (harness, sessionID) = try await startRecording()
            harness.useCase.permissionDidChange(SessionLocationRecordingUseCaseHarness.permission(level))

            await harness.waitForSubscriptions(subscribed: 1, terminated: 1)
            await harness.waitForEventKinds([.recording, expectedKind], for: sessionID)
            harness.tearDown()
        }
    }

    /// 取得不可が届くと `locationUnavailable` を書いて購読を続け、位置が戻ると `recording` を書きます。
    ///
    /// 責務: 取得可否の報告が事象になり、購読が取消されず、復帰後の位置も保存されることを確認します。
    func testUnavailabilityAndRecoveryAreRecordedAsEvents() async throws {
        let (harness, sessionID) = try await startRecording()
        harness.subscription.yield(.unavailable(.temporarilyUnavailable))
        await harness.waitForEventKinds([.recording, .locationUnavailable], for: sessionID)

        try await harness.yieldFixAndWaitSaved(index: 2, to: sessionID)
        await harness.waitForEventKinds([.recording, .locationUnavailable, .recording], for: sessionID)
        await harness.settle()
        XCTAssertEqual(harness.subscription.subscribeCallCount, 1)
        XCTAssertEqual(harness.subscription.terminationCount, 0)
        XCTAssertEqual(harness.repository.storedFixes(for: sessionID).count, 2)
    }

    /// 設定オフのまま前面・背面や許可が変わっても、同じ種類の事象を続けて書きません。
    ///
    /// 責務: 判定の種類が変わらない間は事象が1行のままで、購読もしないことを確認します。
    func testSameKindIsNotWrittenTwiceWhileDisabled() async {
        let made = SessionLocationRecordingUseCaseHarness(
            isRecordingEnabled: false, permission: SessionLocationRecordingUseCaseHarness.permission(.always), isForeground: true
        )
        harness = made
        let sessionID = ConnectionSessionID()
        made.useCase.activeSessionDidChange(sessionID)
        await made.waitForEventKinds([.disabledBySetting], for: sessionID)

        made.useCase.foregroundDidChange(isForeground: false)
        made.useCase.foregroundDidChange(isForeground: true)
        made.useCase.permissionDidChange(SessionLocationRecordingUseCaseHarness.permission(.whenInUse))
        made.useCase.permissionDidChange(SessionLocationRecordingUseCaseHarness.permission(.always))
        made.useCase.recordingPreferenceDidChange(isEnabled: false)
        await made.settle()
        XCTAssertEqual(made.repository.storedEventKinds(for: sessionID), [.disabledBySetting])
        XCTAssertEqual(made.subscription.subscribeCallCount, 0)
    }

    /// 記録中に判定が変わらない通知が続いても、事象を重ねず購読し直しません。
    ///
    /// 責務: 同じ前面・許可・設定の通知で事象が `recording` の1行のまま、購読が1件のままであることを確認します。
    func testSameKindIsNotWrittenTwiceWhileRecording() async throws {
        let (harness, sessionID) = try await startRecording()
        harness.useCase.foregroundDidChange(isForeground: true)
        harness.useCase.permissionDidChange(SessionLocationRecordingUseCaseHarness.permission(.always))
        harness.useCase.recordingPreferenceDidChange(isEnabled: true)
        harness.useCase.foregroundDidChange(isForeground: false)
        await harness.settle()
        XCTAssertEqual(harness.repository.storedEventKinds(for: sessionID), [.recording])
        XCTAssertEqual(harness.subscription.subscribeCallCount, 1)
        XCTAssertEqual(harness.subscription.terminationCount, 0)
    }
}
