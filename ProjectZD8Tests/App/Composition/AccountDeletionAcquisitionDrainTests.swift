import Foundation
import XCTest
@testable import ProjectZD8

/// `AccountDeletionAcquisitionDrain` が、自動アップロードを止め、記録の終了を要求し、接続が切れるまで上限付きで待つことを検証します。
///
/// 仕様: 既定は100ms×300回。上限を超えたら `.timedOut`。待ちは注入した sleep で行い、実時間は使わない。
@MainActor
final class AccountDeletionAcquisitionDrainTests: XCTestCase {
    /// 各テストのモデル部品です。
    private var fixtures: [LiveTelemetryModelFixture] = []

    /// 動いている取得を止め、期限待ちを解放します。
    ///
    /// 責務: テストごとに応答待ちの要求・取得Taskを片付けます。
    override func tearDown() async throws {
        for fixture in fixtures { await fixture.tearDown() }
        fixtures.removeAll()
        try await super.tearDown()
    }

    /// 待ちの上限と間隔の既定値が仕様どおり(100ms×300回)であることを検証します。
    ///
    /// 責務: 既定値の定数を確認します。
    func testDefaultsAre300PollsOf100Milliseconds() {
        XCTAssertEqual(AccountDeletionAcquisitionDrain.defaultMaximumPollCount, 300)
        XCTAssertEqual(AccountDeletionAcquisitionDrain.defaultPollInterval, .milliseconds(100))
    }

    /// 取得していなければ、自動アップロードを止めて終了を要求し、例外なく戻ることを検証します。
    ///
    /// 責務: 停止処理が1回呼ばれ、待ちが上限内で終わり、接続が無いことを確認します。
    func testIdleCompletesAfterSuspendingUpload() async throws {
        let fixture = make()
        let sleeps = SleepProbe { await Task.yield() }
        var suspendCount = 0
        let drain = AccountDeletionAcquisitionDrain(
            liveTelemetry: fixture.model,
            suspendAutomaticUpload: { suspendCount += 1 },
            maximumPollCount: 100_000,
            pollInterval: .milliseconds(7),
            sleep: { try await sleeps.sleep($0) }
        )

        try await drain.endAcquisitionAndWaitUntilSaved()

        XCTAssertEqual(suspendCount, 1)
        XCTAssertFalse(fixture.model.state.isConnectionActive)
    }

    /// 取得中なら、アップロード停止の後に `accountSignedOut` で終了を要求し、接続が切れるまで待つことを検証します。
    ///
    /// 責務: 停止が終了要求より先であること、終了理由、待機後に接続が無いこと、sleep へ渡す間隔を確認します。
    func testActiveAcquisitionIsEndedAndWaitedFor() async throws {
        let fixture = make()
        fixture.start()
        XCTAssertTrue(fixture.model.state.isConnectionActive)
        let sleeps = SleepProbe { await Task.yield() }
        var phaseAtSuspend: LiveTelemetryState.Phase?
        let drain = AccountDeletionAcquisitionDrain(
            liveTelemetry: fixture.model,
            suspendAutomaticUpload: { phaseAtSuspend = fixture.model.state.phase },
            maximumPollCount: 100_000,
            pollInterval: .milliseconds(7),
            sleep: { try await sleeps.sleep($0) }
        )

        try await drain.endAcquisitionAndWaitUntilSaved()

        XCTAssertEqual(phaseAtSuspend, .reading, "終了を要求する前に自動アップロードを止める必要があります。")
        XCTAssertFalse(fixture.model.state.isConnectionActive)
        XCTAssertEqual(fixture.notifications.endReasons, [.accountSignedOut])
        XCTAssertGreaterThanOrEqual(sleeps.count, 1)
        XCTAssertEqual(Set(sleeps.durations), [.milliseconds(7)])
    }

    /// 上限まで接続が切れなければ、上限回数だけ待って `.timedOut` で失敗することを検証します。
    ///
    /// 責務: sleep ごとに取得を再開して接続中を保ち、上限回数の sleep の後に `.timedOut` になることを確認します。
    func testTimesOutAfterMaximumPollCountWhenConnectionNeverEnds() async {
        let fixture = make()
        fixture.start()
        let sleeps = SleepProbe { await MainActor.run { fixture.start() } }
        let drain = AccountDeletionAcquisitionDrain(
            liveTelemetry: fixture.model,
            suspendAutomaticUpload: {
                // このテストでは自動アップロードの停止を観測しないため、何もしない。
            },
            maximumPollCount: 5,
            pollInterval: .milliseconds(1),
            sleep: { try await sleeps.sleep($0) }
        )

        do {
            try await drain.endAcquisitionAndWaitUntilSaved()
            XCTFail("接続が切れないのに待ちが成功しました。")
        } catch {
            XCTAssertEqual(error as? AccountDeletionAcquisitionDrainError, .timedOut)
        }

        XCTAssertEqual(sleeps.count, 5)
        XCTAssertTrue(fixture.model.state.isConnectionActive)
    }

    /// 上限が0回なら、待たずに、接続中であれば `.timedOut` で失敗することを検証します。
    ///
    /// 責務: 上限の境界(0回)で sleep が呼ばれず、停止処理と終了要求だけが行われることを確認します。
    func testZeroMaximumPollCountTimesOutWithoutSleeping() async {
        let fixture = make()
        fixture.start()
        let sleeps = SleepProbe()
        var suspendCount = 0
        let drain = AccountDeletionAcquisitionDrain(
            liveTelemetry: fixture.model,
            suspendAutomaticUpload: { suspendCount += 1 },
            maximumPollCount: 0,
            sleep: { try await sleeps.sleep($0) }
        )

        do {
            try await drain.endAcquisitionAndWaitUntilSaved()
            XCTFail("接続中のまま上限0回の待ちが成功しました。")
        } catch {
            XCTAssertEqual(error as? AccountDeletionAcquisitionDrainError, .timedOut)
        }

        XCTAssertEqual(sleeps.count, 0)
        XCTAssertEqual(suspendCount, 1)
        XCTAssertEqual(fixture.model.state.phase, .stopping)
    }

    /// 待ちの途中でキャンセルされたら、そのエラーを伝えることを検証します。
    ///
    /// 責務: sleep が `CancellationError` を投げた時に、`.timedOut` へ変換せず伝えることを確認します。
    func testCancellationDuringSleepIsPropagated() async {
        let fixture = make()
        fixture.start()
        let sleeps = SleepProbe { throw CancellationError() }
        let drain = AccountDeletionAcquisitionDrain(
            liveTelemetry: fixture.model,
            suspendAutomaticUpload: {
                // このテストでは自動アップロードの停止を観測しないため、何もしない。
            },
            maximumPollCount: 5,
            sleep: { try await sleeps.sleep($0) }
        )

        do {
            try await drain.endAcquisitionAndWaitUntilSaved()
            XCTFail("キャンセルされたのに待ちが成功しました。")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertEqual(sleeps.count, 1)
    }

    /// 後片付けの対象にしたモデル部品を作ります。
    ///
    /// 責務: 記録ポートなしの標準カタログのモデル部品を返します。
    /// - Returns: モデル部品。
    private func make() -> LiveTelemetryModelFixture {
        let fixture = LiveTelemetryModelFixture(catalog: LiveTelemetryTestDefinitions.standard([0x0C]))
        fixtures.append(fixture)
        return fixture
    }
}

/// 注入する sleep の呼び出しを数えて記録し、任意の動作を差し込めるテスト用の部品です。
private final class SleepProbe: @unchecked Sendable {
    /// 排他用のロックです。
    private let lock = NSLock()

    /// 呼び出し回数です。
    private var storedCount = 0

    /// 渡された間隔です。
    private var storedDurations: [Duration] = []

    /// 呼び出しごとに実行する動作です。
    private let action: @Sendable () async throws -> Void

    /// 動作を指定して生成します。
    ///
    /// 責務: sleep の代わりに実行する動作を保持します。省略時は何もしません。
    /// - Parameter action: 呼び出しごとに実行する動作。
    init(action: @escaping @Sendable () async throws -> Void = {
        // 省略時は待機の代わりに何も実行しない。
    }) {
        self.action = action
    }

    /// 呼び出し回数です。
    var count: Int { lock.withLock { storedCount } }

    /// 渡された間隔の履歴です。
    var durations: [Duration] { lock.withLock { storedDurations } }

    /// 呼び出しを記録して動作を実行します。
    ///
    /// 責務: 実時間を待たず、回数と間隔を記録して指定の動作だけを行います。
    /// - Parameter duration: 渡された間隔。
    func sleep(_ duration: Duration) async throws {
        lock.withLock {
            storedCount += 1
            storedDurations.append(duration)
        }
        try await action()
    }
}
