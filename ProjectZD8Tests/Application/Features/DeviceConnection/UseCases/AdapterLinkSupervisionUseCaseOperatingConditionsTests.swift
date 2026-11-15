import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` の稼働条件(サインイン・既定アダプター・BLE)とリンクの開始・停止を検証します。
@MainActor
final class AdapterLinkSupervisionUseCaseOperatingConditionsTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// テスト中に組み立てた手段です。終了時に保留を終わらせます。
    private var harnesses: [AdapterLinkSupervisionHarness] = []

    /// 責務: 保留中の非同期呼び出しを全て終わらせます。
    override func tearDown() async throws {
        harnesses.forEach { $0.finishAllPending() }
        harnesses.removeAll()
        try await super.tearDown()
    }

    /// 責務: 既定アダプター設定と自動記録設定を指定して手段を組み立て、終了処理の対象に加えます。
    private func makeHarness(defaultAdapter: DefaultAdapterPreference? = F.blePreference) -> AdapterLinkSupervisionHarness {
        let harness = AdapterLinkSupervisionHarness(defaultAdapter: defaultAdapter)
        harnesses.append(harness)
        return harness
    }

    /// 稼働条件を満たさない時、リンクは開始されず、`ready` が届いても初期化しないことを検証します。
    ///
    /// 責務: 指定の手段でリンクの開始・初期化・通知・記録が1件も起きず待機のままであることを確認します。
    private func assertLinkStaysIdle(_ harness: AdapterLinkSupervisionHarness, file: StaticString = #filePath, line: UInt = #line) async throws {
        harness.link.emit(.ready)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.link.startedPreferences, [], file: file, line: line)
        XCTAssertEqual(harness.initialization.responses.callCount, 0, file: file, line: line)
        XCTAssertEqual(harness.useCase.state, .standby, file: file, line: line)
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [], file: file, line: line)
        XCTAssertEqual(harness.recordingControl.startRequests, [], file: file, line: line)
    }

    /// 未サインインでは、既定アダプターがBLEでもリンクを開始しません。
    ///
    /// 責務: `start()` だけでは待機のままであることを確認します。
    func testSignedOutDoesNotStartLink() async throws {
        let harness = makeHarness()
        harness.useCase.authenticationDidChange(isSignedIn: false)
        harness.useCase.start()
        try await assertLinkStaysIdle(harness)
    }

    /// 既定アダプター未設定ではリンクを開始しません。
    ///
    /// 責務: サインイン済みでも既定がなければ待機のままであることを確認します。
    func testMissingDefaultAdapterDoesNotStartLink() async throws {
        let harness = makeHarness(defaultAdapter: nil)
        harness.startSignedIn()
        try await assertLinkStaysIdle(harness)
    }

    /// 既定アダプターがBluetooth Classicならリンクを開始しません。
    ///
    /// 責務: BLE以外の方式で待機のままであることを確認します。
    func testBluetoothClassicDoesNotStartLink() async throws {
        let harness = makeHarness(defaultAdapter: F.classicPreference)
        harness.startSignedIn()
        try await assertLinkStaysIdle(harness)
    }

    /// 既定アダプターがシリアルならリンクを開始しません。
    ///
    /// 責務: シリアル方式で待機のままであることを確認します。
    func testSerialDoesNotStartLink() async throws {
        let harness = makeHarness(defaultAdapter: F.serialPreference)
        harness.startSignedIn()
        try await assertLinkStaysIdle(harness)
    }

    /// `start()` を呼ぶまではサインイン済みでもリンクを開始しません。
    ///
    /// 責務: 監視の開始前の認証状態の変化だけでリンクが動かないことを確認します。
    func testSignInBeforeStartDoesNotStartLink() async throws {
        let harness = makeHarness()
        harness.useCase.authenticationDidChange(isSignedIn: true)
        try await assertLinkStaysIdle(harness)
    }

    /// サインイン済み・既定がBLEなら、既定アダプターの設定でリンクを1回開始します。
    ///
    /// 責務: 開始の引数と回数、停止しないことを確認します。
    func testSignedInWithBLEDefaultStartsLinkOnce() {
        let harness = makeHarness()
        harness.startSignedIn()
        XCTAssertEqual(harness.link.startedPreferences, [F.blePreference])
        XCTAssertEqual(harness.link.stopCount, 0)
        XCTAssertEqual(harness.useCase.state, .standby)
    }

    /// 開始後にサインインしてもリンクを開始します。
    ///
    /// 責務: 認証状態の変化が稼働条件の再評価になることを確認します。
    func testSignInAfterStartStartsLink() {
        let harness = makeHarness()
        harness.useCase.start()
        XCTAssertEqual(harness.link.startedPreferences, [])
        harness.useCase.authenticationDidChange(isSignedIn: true)
        XCTAssertEqual(harness.link.startedPreferences, [F.blePreference])
    }

    /// `start()` の重複・同じ認証状態・同じ既定アダプターの再通知ではリンクを二重に開始しません。
    ///
    /// 責務: 開始1回・停止0回のままで、通知の準備も1回であることを確認します。
    func testRepeatedInputsDoNotStartLinkTwice() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        harness.useCase.start()
        harness.useCase.authenticationDidChange(isSignedIn: true)
        harness.useCase.defaultAdapterPreferenceDidChange()
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.link.startedPreferences, [F.blePreference])
        XCTAssertEqual(harness.link.stopCount, 0)
        XCTAssertLessThanOrEqual(harness.notifications.prepareCount, 1)
    }

    /// 同じ `ready` の再通知や `start()` の重複で初期化が二重に走りません。
    ///
    /// 責務: 初期化の呼び出しが1回のままであることを確認します。
    func testRepeatedReadyAndStartDoNotInitializeTwice() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await harness.makeLinkReady()
        harness.link.emit(.ready)
        harness.useCase.start()
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.initialization.responses.callCount, 1)
        XCTAssertEqual(harness.link.startedPreferences.count, 1)
    }

    /// 既定アダプターを削除したらリンクを止め、通知を取り下げて待機へ戻ります。
    ///
    /// 責務: 車両確認中に既定が消えた時の停止・取り下げ・待機を確認します。
    func testRemovingDefaultAdapterStopsLink() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        let dismissals = harness.notifications.dismissCount
        harness.preferenceStore.preference = nil
        harness.useCase.defaultAdapterPreferenceDidChange()
        XCTAssertEqual(harness.link.stopCount, 1)
        XCTAssertGreaterThan(harness.notifications.dismissCount, dismissals)
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.link.startedPreferences, [F.blePreference])
    }

    /// 既定アダプターをBLE以外(Classic・シリアル)へ変えたらリンクを止めます。
    ///
    /// 責務: 方式の変更で停止し、新しいリンクを開始しないことを確認します。
    func testChangingDefaultAdapterToNonBLEStopsLink() {
        for preference in [F.classicPreference, F.serialPreference] {
            let harness = makeHarness()
            harness.startSignedIn()
            harness.preferenceStore.preference = preference
            harness.useCase.defaultAdapterPreferenceDidChange()
            XCTAssertEqual(harness.link.stopCount, 1, "\(preference.connectionTransport)")
            XCTAssertEqual(harness.link.startedPreferences, [F.blePreference], "\(preference.connectionTransport)")
        }
    }

    /// 別のBLEアダプターへ変えたら、止めてから新しい設定で開始し直し、新しいリンクの `ready` で初期化します。
    ///
    /// 責務: 停止→開始の順序、開始の引数、切替後のリンクで監視が続くことを確認します。
    func testSwitchingToOtherBLEAdapterRestartsLinkAndInitializesOnReady() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        harness.preferenceStore.preference = F.otherBLEPreference
        harness.useCase.defaultAdapterPreferenceDidChange()
        XCTAssertEqual(harness.link.calls, ["start:ble-a", "stop", "start:ble-b"])
        XCTAssertEqual(harness.link.startedPreferences, [F.blePreference, F.otherBLEPreference])
        XCTAssertEqual(harness.useCase.state, .standby)

        try await harness.makeLinkReady()
        XCTAssertEqual(harness.useCase.state, .initializing(linkReadyAt: harness.clock.now))
    }

    /// サインアウト後に再びサインインすると、リンクを開始し直し、`ready` で初期化します。
    ///
    /// 責務: 停止したリンクの最後の `ready` が、次のリンクの `ready` を再通知扱いにしないことを確認します。
    func testSignInAgainAfterSignOutRestartsAndInitializes() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        harness.useCase.authenticationDidChange(isSignedIn: false)
        harness.useCase.authenticationDidChange(isSignedIn: true)
        XCTAssertEqual(harness.link.startedPreferences, [F.blePreference, F.blePreference])
        try await harness.makeLinkReady()
        XCTAssertEqual(harness.initialization.responses.callCount, 2)
    }

    /// `stop()` でリンクを止め、再び `start()` すると開始し直します。
    ///
    /// 責務: 監視の停止・再開がリンクの停止・開始になることを確認します。
    func testStopStopsLinkAndStartRestarts() {
        let harness = makeHarness()
        harness.startSignedIn()
        harness.useCase.stop()
        XCTAssertEqual(harness.link.stopCount, 1)
        harness.useCase.start()
        XCTAssertEqual(harness.link.startedPreferences, [F.blePreference, F.blePreference])
    }

    /// 状態が変わるたびに `stateDidChange` へ新しい状態が届きます。
    ///
    /// 責務: 待機→初期化中→確認中の変化が順に通知されることを確認します。
    func testStateDidChangeReportsTransitions() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        XCTAssertEqual(harness.observedStates.count, 2)
        XCTAssertEqual(harness.observedStates.first, .initializing(linkReadyAt: F.referenceDate))
        XCTAssertEqual(harness.observedStates.last, harness.useCase.state)
        XCTAssertTrue(harness.isConfirming(.probing))
    }
}
