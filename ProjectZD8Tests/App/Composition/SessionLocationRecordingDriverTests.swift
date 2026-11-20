import Foundation
import XCTest
@testable import ProjectZD8

/// `SessionLocationRecordingDriver` が、現在のセッション・許可・前面状態を `SessionLocationRecordingUseCase` と設定モデルへ伝えることを検証します。
///
/// 実物のライフサイクルモデルとユースケースを使い、リポジトリの spy に書かれた事象行と購読 fake の購読回数で結果を観測します。
@MainActor
final class SessionLocationRecordingDriverTests: XCTestCase {
    /// 1回のテストが使う、Driver とその依存の一式です。
    private struct Fixture {
        /// ユースケースと fake・spy をまとめた土台です。
        let harness: SessionLocationRecordingUseCaseHarness
        /// 許可の fake です。
        let authorization: LocationAuthorizationFake
        /// 実物のライフサイクルモデルです。
        let lifecycle: ConnectionSessionLifecycleModel
        /// 設定モデルです。
        let settings: RouteRecordingSettingsModel
        /// テスト対象です。
        let driver: SessionLocationRecordingDriver
    }

    /// 始まる順に払い出すセッション ID です。
    private let sessionIDs = [
        ConnectionSessionID(rawValue: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!),
        ConnectionSessionID(rawValue: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!)
    ]
    /// 常に許可の許可状態です。
    private let alwaysPermission = LocationPermission(level: .always, isPreciseAccuracy: true)
    /// 使用中のみの許可状態です。
    private let whenInUsePermission = LocationPermission(level: .whenInUse, isPreciseAccuracy: true)
    /// 拒否の許可状態です。
    private let deniedPermission = LocationPermission(level: .denied, isPreciseAccuracy: false)

    /// 一式を組み立て、テスト終了時の後始末を登録します。
    ///
    /// 責務: 設定オン・前面の条件で Driver を作ります。Driver は `launch()` していません。
    /// - Parameter permission: 許可状態の初期値。
    /// - Returns: 組み立てた一式。
    private func makeFixture(permission: LocationPermission) -> Fixture {
        let harness = SessionLocationRecordingUseCaseHarness(isRecordingEnabled: true, permission: permission, isForeground: true)
        let authorization = LocationAuthorizationFake(currentPermission: permission)
        var ids = sessionIDs.makeIterator()
        let lifecycle = ConnectionSessionLifecycleModel(
            repository: SavingConnectionSessionRepositorySpy(),
            makeID: { ids.next() ?? ConnectionSessionID() }
        )
        let settings = RouteRecordingSettingsModel(
            preference: RouteRecordingPreferenceUseCase(preferencePort: RouteRecordingPreferenceStoreFake(isEnabled: true)),
            authorization: authorization
        )
        let driver = SessionLocationRecordingDriver(
            useCase: harness.useCase, lifecycle: lifecycle, authorization: authorization, settings: settings
        )
        lifecycle.send(.accountIdentifierChanged("account"))
        addTeardownBlock { @MainActor in
            harness.tearDown()
            authorization.finishAll()
        }
        return Fixture(harness: harness, authorization: authorization, lifecycle: lifecycle, settings: settings, driver: driver)
    }

    /// 開始済みのセッション ID を返します。
    ///
    /// 責務: 現在のセッションが無ければテストを失敗させます。
    /// - Parameter fixture: 一式。
    /// - Returns: 現在のセッション ID。
    private func activeID(_ fixture: Fixture) throws -> ConnectionSessionID {
        try XCTUnwrap(fixture.lifecycle.activeSession?.id, "セッションが開始されていません")
    }

    /// launch の後に開始したセッションの ID へ、事象が書かれます。
    ///
    /// 責務: 開始が UseCase へ伝わり、常に許可・設定オンで `recording` が書かれ購読されることを確認します。
    func testSessionStartedAfterLaunchRecordsEvent() async throws {
        let fixture = makeFixture(permission: alwaysPermission)
        fixture.driver.launch()

        fixture.lifecycle.send(.startRequested)

        let id = try activeID(fixture)
        XCTAssertEqual(id, sessionIDs[0])
        await fixture.harness.waitForEventKinds([.recording], for: id)
        await fixture.harness.waitForSubscriptions(subscribed: 1, terminated: 0)
    }

    /// launch の時点で既にあるセッションにも、事象が書かれます。
    ///
    /// 責務: 起動前に始まっていたセッションを launch が UseCase へ伝えることを確認します。
    func testSessionAlreadyActiveAtLaunchRecordsEvent() async throws {
        let fixture = makeFixture(permission: alwaysPermission)
        fixture.lifecycle.send(.startRequested)
        let id = try activeID(fixture)

        fixture.driver.launch()

        await fixture.harness.waitForEventKinds([.recording], for: id)
        await fixture.harness.waitForSubscriptions(subscribed: 1, terminated: 0)
    }

    /// launch の前に始まったセッションは、launch までは伝わりません。
    ///
    /// 責務: launch 前は事象も購読も無く、launch 後に初めて書かれることを確認します。
    func testSessionIsNotNotifiedBeforeLaunch() async throws {
        let fixture = makeFixture(permission: alwaysPermission)
        fixture.lifecycle.send(.startRequested)
        let id = try activeID(fixture)

        await LocationRecordingBoundedWaiter.settle(polls: 120)

        XCTAssertEqual(fixture.harness.repository.storedEventKinds(for: id), [])
        XCTAssertEqual(fixture.harness.subscription.subscribeCallCount, 0)
        fixture.driver.launch()
        await fixture.harness.waitForEventKinds([.recording], for: id)
    }

    /// launch を2回呼んでも、同じセッションの事象は1行のままです。
    ///
    /// 責務: 二重に観測しても事象行・購読が増えないことを確認します。
    func testLaunchTwiceKeepsSingleEventRow() async throws {
        let fixture = makeFixture(permission: alwaysPermission)
        fixture.driver.launch()
        fixture.driver.launch()

        fixture.lifecycle.send(.startRequested)

        let id = try activeID(fixture)
        await fixture.harness.waitForEventKinds([.recording], for: id)
        await LocationRecordingBoundedWaiter.settle(polls: 120)
        XCTAssertEqual(fixture.harness.repository.storedEventKinds(for: id), [.recording])
        XCTAssertEqual(fixture.harness.subscription.subscribeCallCount, 1)
    }

    /// セッションを終了すると、購読が取消されます。
    ///
    /// 責務: 終了が UseCase へ伝わり、購読の流れが終了することを確認します。
    func testEndingSessionCancelsSubscription() async throws {
        let fixture = makeFixture(permission: alwaysPermission)
        fixture.driver.launch()
        fixture.lifecycle.send(.startRequested)
        await fixture.harness.waitForSubscriptions(subscribed: 1, terminated: 0)

        fixture.lifecycle.send(.endRequested(.userDisconnected))

        XCTAssertNil(fixture.lifecycle.activeSession)
        await fixture.harness.waitForSubscriptions(subscribed: 1, terminated: 1)
    }

    /// 終了後に新しいセッションを始めると、新しい ID へ事象が書かれます。
    ///
    /// 責務: 2つ目のセッションが別 ID として伝わり、再び購読されることを確認します。
    func testNewSessionAfterEndRecordsEventForNewID() async throws {
        let fixture = makeFixture(permission: alwaysPermission)
        fixture.driver.launch()
        fixture.lifecycle.send(.startRequested)
        await fixture.harness.waitForSubscriptions(subscribed: 1, terminated: 0)
        fixture.lifecycle.send(.endRequested(.userDisconnected))
        await fixture.harness.waitForSubscriptions(subscribed: 1, terminated: 1)

        fixture.lifecycle.send(.startRequested)

        let newID = try activeID(fixture)
        XCTAssertEqual(newID, sessionIDs[1])
        await fixture.harness.waitForEventKinds([.recording], for: newID)
        await fixture.harness.waitForSubscriptions(subscribed: 2, terminated: 1)
    }

    /// アカウントが変わって現在のセッションが外れると、購読が取消されます。
    ///
    /// 責務: `activeSession` がアカウント変更で nil になる経路が UseCase へ伝わることを確認します。
    func testAccountChangeCancelsSubscription() async throws {
        let fixture = makeFixture(permission: alwaysPermission)
        fixture.driver.launch()
        fixture.lifecycle.send(.startRequested)
        await fixture.harness.waitForSubscriptions(subscribed: 1, terminated: 0)

        fixture.lifecycle.send(.accountIdentifierChanged(nil))

        XCTAssertNil(fixture.lifecycle.activeSession)
        await fixture.harness.waitForSubscriptions(subscribed: 1, terminated: 1)
    }

    /// 許可が拒否へ変わると、記録中のセッションに事象が書かれ、設定の状態も拒否になります。
    ///
    /// 責務: 許可の変化が UseCase と設定モデルの両方へ伝わることを確認します。
    func testPermissionDeniedReachesUseCaseAndSettings() async throws {
        let fixture = makeFixture(permission: alwaysPermission)
        fixture.driver.launch()
        fixture.lifecycle.send(.startRequested)
        let id = try activeID(fixture)
        await fixture.harness.waitForEventKinds([.recording], for: id)

        fixture.authorization.sendPermissionChange(deniedPermission)

        await fixture.harness.waitForEventKinds([.recording, .authorizationDenied], for: id)
        await LocationRecordingBoundedWaiter.waitUntil("設定の状態が拒否になる") {
            fixture.settings.section.status == .denied
        }
        await fixture.harness.waitForSubscriptions(subscribed: 1, terminated: 1)
    }

    /// 使用中のみの許可で背面へ入ると購読が取消され、前面へ戻ると再び購読されます。
    ///
    /// 責務: 前面・背面の通知が UseCase へ伝わり、事象行と購読が切り替わることを確認します。
    func testBackgroundAndForegroundWithWhenInUseTogglesSubscription() async throws {
        let fixture = makeFixture(permission: whenInUsePermission)
        fixture.driver.launch()
        fixture.lifecycle.send(.startRequested)
        let id = try activeID(fixture)
        await fixture.harness.waitForEventKinds([.recording], for: id)

        fixture.driver.appDidEnterBackground()

        await fixture.harness.waitForEventKinds([.recording, .backgroundWithoutAlwaysAuthorization], for: id)
        await fixture.harness.waitForSubscriptions(subscribed: 1, terminated: 1)

        fixture.driver.appDidBecomeActive()

        await fixture.harness.waitForEventKinds([.recording, .backgroundWithoutAlwaysAuthorization, .recording], for: id)
        await fixture.harness.waitForSubscriptions(subscribed: 2, terminated: 1)
    }

    /// 常に許可なら、背面へ入っても購読を続けます。
    ///
    /// 責務: 背面通知が常に許可の記録を止めないことを確認します。
    func testBackgroundWithAlwaysPermissionKeepsSubscription() async throws {
        let fixture = makeFixture(permission: alwaysPermission)
        fixture.driver.launch()
        fixture.lifecycle.send(.startRequested)
        let id = try activeID(fixture)
        await fixture.harness.waitForEventKinds([.recording], for: id)

        fixture.driver.appDidEnterBackground()
        await LocationRecordingBoundedWaiter.settle(polls: 120)

        XCTAssertEqual(fixture.harness.repository.storedEventKinds(for: id), [.recording])
        XCTAssertEqual(fixture.harness.subscription.terminationCount, 0)
    }
}
