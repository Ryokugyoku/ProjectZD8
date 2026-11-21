import XCTest
@testable import ProjectZD8

/// `SessionLocationRecordingUseCase` がセッション開始時の条件から購読の有無と事象を決めることを検証します。
@MainActor
final class SessionLocationRecordingUseCaseTests: XCTestCase {
    /// 現在のテストの土台です(後始末に使います)。
    private var harness: SessionLocationRecordingUseCaseHarness?

    /// 初期条件を指定して土台を作ります。
    ///
    /// 責務: 土台を生成し、後始末の対象として保持します。
    /// - Parameters:
    ///   - isRecordingEnabled: 走行ルート記録設定の初期値。
    ///   - permission: 許可状態の初期値。
    ///   - isForeground: 前面にいるかどうかの初期値。
    /// - Returns: 生成した土台。
    private func makeHarness(
        isRecordingEnabled: Bool,
        permission: LocationPermission,
        isForeground: Bool
    ) -> SessionLocationRecordingUseCaseHarness {
        let made = SessionLocationRecordingUseCaseHarness(
            isRecordingEnabled: isRecordingEnabled, permission: permission, isForeground: isForeground
        )
        harness = made
        return made
    }

    /// 購読と記録のタスクを後始末します。
    ///
    /// 責務: セッションを外し、残った流れを終えます。
    override func tearDown() async throws {
        harness?.tearDown()
        harness = nil
        try await super.tearDown()
    }

    /// 設定オフで始まると購読せず、注入した時刻で `disabledBySetting` を1行書きます。
    ///
    /// 責務: 設定オフの判定が購読を始めず、事象の時刻が注入した時計に従うことを確認します。
    func testDisabledSettingDoesNotSubscribeAndWritesEvent() async throws {
        let harness = makeHarness(isRecordingEnabled: false, permission: Self.always, isForeground: true)
        let sessionID = ConnectionSessionID()
        harness.useCase.activeSessionDidChange(sessionID)

        await harness.waitForEventKinds([.disabledBySetting], for: sessionID)
        XCTAssertEqual(try harness.repository.events(for: sessionID).map(\.occurredAt), [SessionLocationRecordingUseCaseHarness.fixedNow])
        await harness.settle()
        XCTAssertEqual(harness.subscription.subscribeCallCount, 0)
    }

    /// 設定オン・常に許可・背面で始まると購読し、`recording` を書き、流した位置をそのセッションへ保存します。
    ///
    /// 責務: 背面開始でも「常に許可」なら取得し、位置がセッションへ保存されることを確認します。
    func testAlwaysInBackgroundSubscribesAndSavesFixes() async throws {
        let harness = makeHarness(isRecordingEnabled: true, permission: Self.always, isForeground: false)
        let sessionID = ConnectionSessionID()
        harness.useCase.activeSessionDidChange(sessionID)

        await harness.waitForEventKinds([.recording], for: sessionID)
        XCTAssertEqual(try harness.repository.events(for: sessionID).map(\.occurredAt), [SessionLocationRecordingUseCaseHarness.fixedNow])
        await harness.waitForSubscriptions(subscribed: 1, terminated: 0)
        let first = try await harness.yieldFixAndWaitSaved(index: 1, to: sessionID)
        let second = try await harness.yieldFixAndWaitSaved(index: 2, to: sessionID)
        XCTAssertEqual(harness.repository.storedFixes(for: sessionID), [first, second])
    }

    /// 使用中のみの許可では、背面で購読せず、前面で購読し、再び背面で取消します。
    ///
    /// 責務: 前面・背面の変化に応じて購読の開始・取消と事象の追記が起きることを確認します。
    func testWhenInUseFollowsForegroundTransitions() async throws {
        let harness = makeHarness(isRecordingEnabled: true, permission: Self.whenInUse, isForeground: false)
        let sessionID = ConnectionSessionID()
        harness.useCase.activeSessionDidChange(sessionID)
        await harness.waitForEventKinds([.backgroundWithoutAlwaysAuthorization], for: sessionID)
        await harness.settle()
        XCTAssertEqual(harness.subscription.subscribeCallCount, 0)

        harness.useCase.foregroundDidChange(isForeground: true)
        await harness.waitForSubscriptions(subscribed: 1, terminated: 0)
        await harness.waitForEventKinds([.backgroundWithoutAlwaysAuthorization, .recording], for: sessionID)
        try await harness.yieldFixAndWaitSaved(index: 1, to: sessionID)

        harness.useCase.foregroundDidChange(isForeground: false)
        await harness.waitForSubscriptions(subscribed: 1, terminated: 1)
        await harness.waitForEventKinds(
            [.backgroundWithoutAlwaysAuthorization, .recording, .backgroundWithoutAlwaysAuthorization], for: sessionID
        )
    }

    /// 概略の位置のみの許可で始まると購読し、`recordingWithReducedAccuracy` を書きます。
    ///
    /// 責務: 精度が低い許可でも取得し、その旨の事象を残すことを確認します。
    func testReducedAccuracySubscribesWithReducedAccuracyEvent() async {
        let reduced = SessionLocationRecordingUseCaseHarness.permission(.always, isPreciseAccuracy: false)
        let harness = makeHarness(isRecordingEnabled: true, permission: reduced, isForeground: true)
        let sessionID = ConnectionSessionID()
        harness.useCase.activeSessionDidChange(sessionID)

        await harness.waitForEventKinds([.recordingWithReducedAccuracy], for: sessionID)
        await harness.waitForSubscriptions(subscribed: 1, terminated: 0)
    }

    /// 対応しないプラットフォームでは、設定オンでも購読せず `unsupportedPlatform` を書きます。
    ///
    /// 責務: プラットフォームの判定が設定より優先されることを確認します。
    func testUnsupportedPlatformDoesNotSubscribeEvenWhenEnabled() async {
        let harness = makeHarness(isRecordingEnabled: true, permission: .unsupportedPlatform, isForeground: true)
        let sessionID = ConnectionSessionID()
        harness.useCase.activeSessionDidChange(sessionID)

        await harness.waitForEventKinds([.unsupportedPlatform], for: sessionID)
        await harness.settle()
        XCTAssertEqual(harness.subscription.subscribeCallCount, 0)
    }

    /// 事象の保存に失敗すると、種類とセッションを診断へ残します。
    ///
    /// 責務: `appendEvent` の失敗が握りつぶされず診断に記録されることを確認します。
    func testEventStorageFailureIsDiagnosed() async {
        let harness = makeHarness(isRecordingEnabled: false, permission: Self.always, isForeground: true)
        harness.repository.setFailsAppendEvent(true)
        let sessionID = ConnectionSessionID()
        harness.useCase.activeSessionDidChange(sessionID)

        let expected = [SessionLocationRecordingDiagnosticsSpy.EventFailure(kind: .disabledBySetting, sessionID: sessionID)]
        await LocationRecordingBoundedWaiter.waitUntil("事象の保存失敗が診断に残る") { harness.diagnostics.eventFailures == expected }
        XCTAssertEqual(harness.repository.storedEventKinds(for: sessionID), [])
    }

    /// セッションが無い間に設定・許可・前面が整うと、次のセッション開始時に購読します。
    ///
    /// 責務: セッション外の状態変化が購読も事象も起こさず、次の開始時の判定に反映されることを確認します。
    func testChangesWithoutSessionEnableNextSession() async {
        let harness = makeHarness(isRecordingEnabled: false, permission: Self.notDetermined, isForeground: false)
        harness.useCase.recordingPreferenceDidChange(isEnabled: true)
        harness.useCase.permissionDidChange(Self.always)
        harness.useCase.foregroundDidChange(isForeground: true)
        await harness.settle()
        XCTAssertEqual(harness.subscription.subscribeCallCount, 0)

        let sessionID = ConnectionSessionID()
        harness.useCase.activeSessionDidChange(sessionID)
        await harness.waitForEventKinds([.recording], for: sessionID)
        await harness.waitForSubscriptions(subscribed: 1, terminated: 0)
    }

    /// セッションが無い間に設定がオフになると、次のセッションは購読せず `disabledBySetting` を書きます。
    ///
    /// 責務: セッション外の設定変更が次の開始時の判定に反映されることを確認します。
    func testPreferenceChangeWithoutSessionDisablesNextSession() async {
        let harness = makeHarness(isRecordingEnabled: true, permission: Self.always, isForeground: true)
        harness.useCase.recordingPreferenceDidChange(isEnabled: false)

        let sessionID = ConnectionSessionID()
        harness.useCase.activeSessionDidChange(sessionID)
        await harness.waitForEventKinds([.disabledBySetting], for: sessionID)
        await harness.settle()
        XCTAssertEqual(harness.subscription.subscribeCallCount, 0)
    }

    /// セッションが無い間の許可と前面の変化も、次のセッション開始時の判定に反映されます。
    ///
    /// 責務: 許可の拒否と背面への移動が、それぞれ次の開始時の事象になることを確認します。
    func testPermissionAndForegroundChangesWithoutSessionApplyToNextSession() async {
        let denied = makeHarness(isRecordingEnabled: true, permission: Self.always, isForeground: true)
        denied.useCase.permissionDidChange(SessionLocationRecordingUseCaseHarness.permission(.denied))
        let deniedSession = ConnectionSessionID()
        denied.useCase.activeSessionDidChange(deniedSession)
        await denied.waitForEventKinds([.authorizationDenied], for: deniedSession)
        denied.tearDown()

        let background = makeHarness(isRecordingEnabled: true, permission: Self.whenInUse, isForeground: true)
        background.useCase.foregroundDidChange(isForeground: false)
        let backgroundSession = ConnectionSessionID()
        background.useCase.activeSessionDidChange(backgroundSession)
        await background.waitForEventKinds([.backgroundWithoutAlwaysAuthorization], for: backgroundSession)
        await background.settle()
        XCTAssertEqual(denied.subscription.subscribeCallCount, 0)
        XCTAssertEqual(background.subscription.subscribeCallCount, 0)
    }

    /// 正確な位置の「常に許可」です。
    private static var always: LocationPermission { SessionLocationRecordingUseCaseHarness.permission(.always) }
    /// 正確な位置の「使用中のみ」です。
    private static var whenInUse: LocationPermission { SessionLocationRecordingUseCaseHarness.permission(.whenInUse) }
    /// 未確定の許可です。
    private static var notDetermined: LocationPermission { SessionLocationRecordingUseCaseHarness.permission(.notDetermined) }
}
