import Foundation
import XCTest
@testable import ProjectZD8

/// 終了直後の走行ルートの即時送信トリガーが、条件・多重実行の抑止・診断を仕様どおりに扱うことを検証します。
///
/// 送信はテスト側のクロージャで受け、実行中の状況は1回目の送信をゲートで止めて作ります。
/// ゲートは `tearDown` で必ず開け、待ちはすべて期限つき(`LocationRecordingBoundedWaiter`)にします。
@MainActor
final class ConnectionSessionLocationTrackUploadTriggerTests: XCTestCase {
    /// セッションのアカウントです。
    private static let account = "account-a"
    /// 失敗の注入に使うエラーの domain です。
    private static let errorDomain = "ConnectionSessionLocationTrackUploadTriggerTests"

    /// 診断の Spy です。
    private let diagnostics = ConnectionSessionLocationTrackSyncDiagnosticsSpy()
    /// 送信に渡されたアカウントです(呼ばれた順)。
    private var uploadAccounts: [String] = []
    /// 1回目の送信をゲートで止めるかどうかです。
    private var blocksFirstUpload = false
    /// ゲートが開いているかどうかです。
    private var isGateOpen = false
    /// ゲートで待っている送信です。
    private var gateContinuations: [CheckedContinuation<Void, Never>] = []
    /// 送信で投げるエラーです(`nil` なら成功)。
    private var uploadError: NSError?
    /// 送信が成功した時に返す報告です。
    private var report = ConnectionSessionLocationTrackUploadReport(
        uploadedSessionIDs: [ConnectionSessionID(), ConnectionSessionID(), ConnectionSessionID()],
        purgedSessionIDs: []
    )
    /// `waitUntilIdle` が戻った回数です。
    private var idleCompletionCount = 0

    /// 責務: 止めたままの送信が残らないよう、ゲートを必ず開けます。
    override func tearDown() async throws {
        openGate()
        try await super.tearDown()
    }

    /// 自動アップロードがオフなら送信しません。
    ///
    /// 責務: 接続済みでもオフの終了では送信も診断も起きないことを確認します。
    func testAutomaticUploadOffDoesNotUpload() async {
        let trigger = makeConnectedTrigger()

        trigger.sessionDidEnd(endedSession(), automaticUploadEnabled: false)
        await waitUntilIdle(trigger)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(uploadAccounts, [])
        XCTAssertEqual(diagnostics.events, [])
    }

    /// 送信が結び付く前(未接続)の終了では送信せず、後から結び付けても送りません。
    ///
    /// 責務: 未接続の時の要求が覚えられず、何も実行されないことを確認します。
    func testNotConnectedDoesNotUpload() async {
        let trigger = ConnectionSessionLocationTrackUploadTrigger(diagnostics: diagnostics)

        trigger.sessionDidEnd(endedSession(), automaticUploadEnabled: true)
        trigger.connect(upload: makeUpload())
        await waitUntilIdle(trigger)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(uploadAccounts, [])
        XCTAssertEqual(diagnostics.events, [])
    }

    /// セッションのアカウントが空なら送信しません。
    ///
    /// 責務: 空のアカウントの終了では送信も診断も起きないことを確認します。
    func testEmptyAccountDoesNotUpload() async {
        let trigger = makeConnectedTrigger()

        trigger.sessionDidEnd(endedSession(accountIdentifier: ""), automaticUploadEnabled: true)
        await waitUntilIdle(trigger)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(uploadAccounts, [])
        XCTAssertEqual(diagnostics.events, [])
    }

    /// 自動アップロードがオンなら、セッションのアカウントで1回だけ送信し、成功の件数を診断に残します。
    ///
    /// 責務: 送信が1回・アカウントが一致・診断が報告の件数の成功1件であることを確認します。
    func testAutomaticUploadOnUploadsOnceWithSessionAccount() async {
        let trigger = makeConnectedTrigger()

        trigger.sessionDidEnd(endedSession(), automaticUploadEnabled: true)
        await LocationRecordingBoundedWaiter.waitUntil("送信が1回呼ばれる") { uploadAccounts.count == 1 }
        await waitUntilIdle(trigger)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(uploadAccounts, [Self.account])
        XCTAssertEqual(diagnostics.events, [.succeeded(uploadedCount: 3)])
    }

    /// 成功の診断には、報告の送信件数をそのまま残します(0件を含む)。
    ///
    /// 責務: 送る対象が無かった実行でも、件数0の成功として残ることを確認します。
    func testSuccessDiagnosticUsesReportCountIncludingZero() async {
        report = ConnectionSessionLocationTrackUploadReport(uploadedSessionIDs: [], purgedSessionIDs: [ConnectionSessionID()])
        let trigger = makeConnectedTrigger()

        trigger.sessionDidEnd(endedSession(), automaticUploadEnabled: true)
        await LocationRecordingBoundedWaiter.waitUntil("成功の診断が残る") { !diagnostics.events.isEmpty }
        await waitUntilIdle(trigger)

        XCTAssertEqual(diagnostics.events, [.succeeded(uploadedCount: 0)])
    }

    /// 実行中に3回要求されても、追加の実行は終了後の1回だけです。
    ///
    /// 責務: 1回目を止めている間の要求で送信が増えず、ゲートを開けた後の合計が2回で止まることを確認します。
    func testRequestsDuringRunCoalesceIntoSingleRerun() async {
        blocksFirstUpload = true
        let trigger = makeConnectedTrigger()

        trigger.sessionDidEnd(endedSession(), automaticUploadEnabled: true)
        await LocationRecordingBoundedWaiter.waitUntil("1回目の送信が始まる") { uploadAccounts.count == 1 }
        for _ in 0..<3 {
            trigger.sessionDidEnd(endedSession(), automaticUploadEnabled: true)
        }
        await LocationRecordingBoundedWaiter.settle()
        XCTAssertEqual(uploadAccounts.count, 1, "実行中に追加の送信が始まりました")

        openGate()
        await LocationRecordingBoundedWaiter.waitUntil("追加の送信が1回呼ばれる") { uploadAccounts.count == 2 }
        await waitUntilIdle(trigger)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(uploadAccounts, [Self.account, Self.account])
        XCTAssertEqual(diagnostics.events, [.succeeded(uploadedCount: 3), .succeeded(uploadedCount: 3)])
    }

    /// 失敗は NSError の domain と code で診断に残り、次の要求も実行されます。
    ///
    /// 責務: 失敗の診断の値と、失敗の後の要求で2回目の送信が成功として残ることを確認します。
    func testFailureIsRecordedWithDomainAndCodeAndNextRequestRuns() async {
        uploadError = NSError(domain: Self.errorDomain, code: 42)
        let trigger = makeConnectedTrigger()

        trigger.sessionDidEnd(endedSession(), automaticUploadEnabled: true)
        await LocationRecordingBoundedWaiter.waitUntil("失敗の診断が残る") { !diagnostics.events.isEmpty }
        await waitUntilIdle(trigger)
        uploadError = nil
        trigger.sessionDidEnd(endedSession(), automaticUploadEnabled: true)
        await LocationRecordingBoundedWaiter.waitUntil("2回目の送信が呼ばれる") { uploadAccounts.count == 2 }
        await waitUntilIdle(trigger)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(uploadAccounts, [Self.account, Self.account])
        XCTAssertEqual(
            diagnostics.events,
            [.failed(errorDomain: Self.errorDomain, errorCode: 42), .succeeded(uploadedCount: 3)]
        )
    }

    /// 送信を結び付けたトリガーを作ります。
    ///
    /// 責務: Spy の診断で生成し、テスト側の送信クロージャを結び付けます。
    /// - Returns: 接続済みのトリガー。
    private func makeConnectedTrigger() -> ConnectionSessionLocationTrackUploadTrigger {
        let trigger = ConnectionSessionLocationTrackUploadTrigger(diagnostics: diagnostics)
        trigger.connect(upload: makeUpload())
        return trigger
    }

    /// テスト側の送信クロージャを作ります。
    ///
    /// 責務: アカウントを記録し、指定があれば1回目をゲートで止め、注入したエラーか報告を返します。
    /// - Returns: 送信クロージャ。
    private func makeUpload() -> @MainActor (String) async throws -> ConnectionSessionLocationTrackUploadReport {
        { [weak self] account in
            guard let self else { throw CancellationError() }
            uploadAccounts.append(account)
            if blocksFirstUpload, uploadAccounts.count == 1 {
                await waitForGate()
            }
            if let uploadError { throw uploadError }
            return report
        }
    }

    /// ゲートが開くまで待ちます。
    ///
    /// 責務: 開いていればすぐ戻り、閉じていれば `openGate()` まで待ちます。
    private func waitForGate() async {
        if isGateOpen { return }
        await withCheckedContinuation { continuation in
            gateContinuations.append(continuation)
        }
    }

    /// ゲートを開け、待っている送信をすべて再開します。
    ///
    /// 責務: 以降の待ちをすぐ戻すようにし、保持した continuation を1回ずつ再開します。
    private func openGate() {
        isGateOpen = true
        let waiting = gateContinuations
        gateContinuations.removeAll()
        waiting.forEach { $0.resume() }
    }

    /// トリガーが待機状態に戻るまで期限つきで待ちます。
    ///
    /// 責務: `waitUntilIdle()` を別タスクで呼び、期限内に戻らなければテストを失敗させて先へ進みます。
    /// - Parameter trigger: 待つトリガー。
    private func waitUntilIdle(_ trigger: ConnectionSessionLocationTrackUploadTrigger) async {
        let expected = idleCompletionCount + 1
        let task = Task { [weak self] in
            await trigger.waitUntilIdle()
            self?.idleCompletionCount += 1
        }
        let returned = await LocationRecordingBoundedWaiter.waitUntil("waitUntilIdle が戻る") {
            idleCompletionCount >= expected
        }
        if !returned { task.cancel() }
    }

    /// 終了済みのセッションを作ります。
    ///
    /// 責務: 指定したアカウントで、終了日時と終了理由を持つセッションを返します。
    /// - Parameter accountIdentifier: セッションのアカウント。`nil` ならテストのアカウント。
    /// - Returns: 終了済みのセッション。
    private func endedSession(accountIdentifier: String? = nil) -> ConnectionSession {
        var session = ConnectionSession(accountIdentifier: accountIdentifier ?? Self.account)
        session.endedAt = Date()
        session.endReason = .userDisconnected
        return session
    }
}
