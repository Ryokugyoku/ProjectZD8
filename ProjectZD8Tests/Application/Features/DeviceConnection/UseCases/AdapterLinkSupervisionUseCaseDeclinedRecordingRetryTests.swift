import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` が、自動記録の開始が辞退・失敗(終了理由なし)で終わった後、リンクが `ready` なら
/// 5秒の待ちを挟んで再初期化・車両確認へ戻り、再び記録開始を要求することを、fake の時計で検証します(S1-3)。
///
/// 待ちは fake の時計の `finishOldestSleep` で明示的に明けさせます。待機はすべて `BLEBoundedWaiter` の回数上限付きで、
/// 上限を超えたら失敗させます。
@MainActor
final class AdapterLinkSupervisionUseCaseDeclinedRecordingRetryTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 辞退後の待ち(延長確認と同じ間隔)の秒数です。
    private let declinedRetrySeconds: TimeInterval = 5

    /// テスト中に組み立てた手段です。終了時に保留を終わらせます。
    private var harnesses: [AdapterLinkSupervisionHarness] = []

    /// 責務: 保留中の非同期呼び出しを全て終わらせます。
    override func tearDown() async throws {
        harnesses.forEach { $0.finishAllPending() }
        harnesses.removeAll()
        try await super.tearDown()
    }

    /// 自動記録オンの手段を組み立て、最初の記録開始要求が出るまで進めます。
    ///
    /// 責務: 開始・リンク `ready`・初期化成功・応答あり・VIN読取を経て、記録中で開始要求が1件出るまで待ちます。
    /// - Returns: 記録中の手段。
    private func automaticRecordingHarness(file: StaticString = #filePath, line: UInt = #line) async throws -> AdapterLinkSupervisionHarness {
        let harness = AdapterLinkSupervisionHarness(isAutomaticRecordingEnabled: true)
        harnesses.append(harness)
        try await harness.driveToConfirming(file: file, line: line)
        try await detectAndWaitForStartRequest(harness, count: 1, file: file, line: line)
        return harness
    }

    /// 保留中の車両確認へ応答ありを返し、VINを読ませて、記録開始要求が指定件数になるまで進めます。
    ///
    /// 責務: 検知から自動記録の開始要求までを1回分進め、記録中になったことを確認します。
    /// - Parameters:
    ///   - harness: 車両確認が1件保留されている手段。
    ///   - count: 待つ記録開始要求の累計件数。
    private func detectAndWaitForStartRequest(
        _ harness: AdapterLinkSupervisionHarness, count: Int, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        try await harness.answerRespondingAndWaitForVINRead(file: file, line: line)
        harness.vinReader.responses.resumeOldest(with: .success(F.vin), file: file, line: line)
        try await harness.wait("\(count)件目の記録開始要求", file: file, line: line) {
            harness.recordingControl.startRequests.count == count
        }
        XCTAssertTrue(harness.isRecording, "記録中でない: \(harness.useCase.state)", file: file, line: line)
    }

    /// 記録開始を辞退させ、待ちが1件要求されるまで進めて、待ちが明ける前は再初期化しないことを確かめます。
    ///
    /// 責務: 終了理由なしの記録終了の後、待ちが5秒で1件要求され、待機のまま初期化の呼び出しが増えないことを確認します。
    /// - Parameter harness: 記録中の手段。
    private func declineAndAssertWaitingBeforeReinitialization(
        _ harness: AdapterLinkSupervisionHarness, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let sleeps = harness.clock.requestedDurations.count
        let initializations = harness.initialization.responses.callCount
        harness.useCase.recordingDidFinish(endReason: nil)
        try await harness.wait("辞退後の待ち", file: file, line: line) { harness.clock.requestedDurations.count == sleeps + 1 }
        XCTAssertEqual(harness.clock.requestedDurations.last, .seconds(declinedRetrySeconds), file: file, line: line)

        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.useCase.state, .standby, "待ちの間は待機", file: file, line: line)
        XCTAssertEqual(harness.initialization.responses.callCount, initializations, "待ちが明ける前に再初期化した", file: file, line: line)
        XCTAssertEqual(harness.vehicleResponse.responses.pendingCount, 0, "待ちが明ける前に車両確認を送った", file: file, line: line)
    }

    /// 辞退 → 5秒待ち → 再初期化 → 車両応答 → 再度の記録開始要求、まで通して進みます。
    ///
    /// 責務: 待ちが明ける前は再初期化せず、5秒進めて待ちを明けさせると、その時刻を窓の起点に再初期化し、
    /// 初期化成功・応答あり・VIN読取を経て2件目の記録開始要求(仕様どおりの接続終端・VIN・判定結果)が出ることを確認します(S1-3)。
    func testDeclinedStartRetriesAfterFiveSecondWaitAndRequestsRecordingAgain() async throws {
        let harness = try await automaticRecordingHarness()
        try await declineAndAssertWaitingBeforeReinitialization(harness)

        XCTAssertTrue(harness.clock.finishOldestSleep(advancingBy: declinedRetrySeconds))
        try await harness.wait("待ち明けの再初期化") { harness.initialization.responses.callCount == 2 }
        XCTAssertEqual(harness.useCase.state, .initializing(linkReadyAt: harness.clock.now))

        try await harness.finishInitialization()
        try await detectAndWaitForStartRequest(harness, count: 2)
        XCTAssertEqual(harness.recordingControl.startRequests.last, F.expectedStartRequest(vin: F.vin))
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 0)
        XCTAssertEqual(harness.link.stopCount, 0)
    }

    /// 辞退が続いても、毎回5秒の待ちを挟んでから再初期化し、待ちを挟まずに空回りしません。
    ///
    /// 責務: 2周続けて辞退させ、各周で待ちが1件ずつ増え、待ちが明けるまで初期化が増えないことを確認します(S1-3)。
    func testRepeatedDeclinesWaitBeforeEveryRetry() async throws {
        let harness = try await automaticRecordingHarness()
        for round in 2...3 {
            try await declineAndAssertWaitingBeforeReinitialization(harness)
            guard harness.clock.finishOldestSleep(advancingBy: declinedRetrySeconds) else { return }
            try await harness.wait("\(round)回目の初期化") { harness.initialization.responses.callCount == round }
            try await harness.finishInitialization()
            try await detectAndWaitForStartRequest(harness, count: round)
        }
        XCTAssertEqual(harness.clock.requestedDurations, [.seconds(5), .seconds(5)])
    }

    /// リンクが `ready` でない時に辞退・失敗で終わったら、待ちを予約せず待機のまま、次の再接続で初期化します(従来どおり)。
    ///
    /// 責務: リンク断の記録中に終了理由なしで終わった後、待ちの要求0件・待機・初期化なしで、再接続で初期化が2回目になることを確認します(S1-3)。
    func testDeclineWithoutReadyLinkDoesNotScheduleWait() async throws {
        let harness = try await automaticRecordingHarness()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        let sleeps = harness.clock.requestedDurations.count
        harness.useCase.recordingDidFinish(endReason: nil)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.clock.requestedDurations.count, sleeps)
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.initialization.responses.callCount, 1)

        try await harness.makeLinkReady()
        XCTAssertEqual(harness.initialization.responses.callCount, 2)
    }

    /// 辞退後の待ちの間にリンクが切れたら、待ちが明けても再初期化しません。
    ///
    /// 責務: 待ちの要求の後のリンク断で待機のまま、古い待ちを明けさせても初期化の呼び出しが増えないことを確認します(S1-3)。
    func testLinkLossDuringDeclinedWaitCancelsReinitialization() async throws {
        let harness = try await automaticRecordingHarness()
        try await declineAndAssertWaitingBeforeReinitialization(harness)
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))

        harness.clock.finishOldestSleep(advancingBy: declinedRetrySeconds)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.initialization.responses.callCount, 1)
    }
}
