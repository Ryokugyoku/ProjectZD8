import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` の車両確認が応答駆動で進み(最短間隔の待ちだけを挟む)、
/// 前面にいる間は窓切れで休止しないことを、fake の時計で検証します。
///
/// 仕様: U3 受け入れ条件 1・3・5・6。時間は fake の時計の `now` を、確認の結果を返す前に進めて表します。
/// 前面にいるかどうかは、最後の `appDidBecomeActive()` の後にバックグラウンドへ移っていないこととします(監視にはまだ背面移行の入力が無いため)。
@MainActor
final class AdapterLinkSupervisionUseCaseResponseDrivenConfirmationTests: XCTestCase {
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

    /// 最初の確認が保留されるまで進めた手段を返します。
    ///
    /// 責務: 手段を組み立てて終了処理の対象に加え、確認中まで進めます(リンク `ready` と初期化は基準時刻)。
    /// - Returns: 確認中の手段。
    private func confirmingHarness(file: StaticString = #filePath, line: UInt = #line) async throws -> AdapterLinkSupervisionHarness {
        let harness = AdapterLinkSupervisionHarness()
        harnesses.append(harness)
        try await harness.driveToConfirming(file: file, line: line)
        return harness
    }

    /// 確認の結果が最短間隔(1秒)ちょうど・直後に返ったら、待たずに次の確認を送ります。
    ///
    /// 責務: 経過1秒・1.001秒の無応答で、待機の要求0件のまま2回目の確認が送られることを確認します(U3 受け入れ条件 1・3)。
    func testResultAtOrAfterMinimumIntervalConfirmsAgainWithoutWaiting() async throws {
        for elapsed in [1.0, 1.001] {
            let harness = try await confirmingHarness()
            harness.clock.now = harness.clock.now.addingTimeInterval(elapsed)
            harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse))
            try await harness.wait("2回目の確認 \(elapsed)") { harness.vehicleResponse.timeouts.count == 2 }
            XCTAssertEqual(harness.clock.requestedDurations, [], "\(elapsed)")
        }
    }

    /// 確認の結果が最短間隔より早く(直前・即時)返ったら、最短間隔に達するまでだけ待ってから次の確認を送ります。
    ///
    /// 責務: 経過0秒・0.999秒の無応答で、待機が1件だけ要求され、その長さが残り時間(1秒以下、正の値)で、待ち明けまでは次の確認が送られないことを確認します(U3 受け入れ条件 3)。
    func testResultBeforeMinimumIntervalWaitsOnlyForRemainder() async throws {
        for elapsed in [0.0, 0.999] {
            let harness = try await confirmingHarness()
            harness.clock.now = harness.clock.now.addingTimeInterval(elapsed)
            harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse))
            try await harness.wait("最短間隔の待ち \(elapsed)") { harness.clock.requestedDurations.count == 1 }
            let remainder = harness.clock.requestedDurations.first ?? .zero
            XCTAssertGreaterThan(remainder, .zero, "\(elapsed)")
            XCTAssertLessThanOrEqual(remainder, .seconds(1) - .milliseconds(Int64(elapsed * 1000)) + .microseconds(100), "\(elapsed)")
            XCTAssertEqual(harness.vehicleResponse.timeouts.count, 1, "待ち明けまでは送らない \(elapsed)")

            harness.clock.finishOldestSleep(advancingBy: 1 - elapsed)
            try await harness.wait("待ち明けの確認 \(elapsed)") { harness.vehicleResponse.timeouts.count == 2 }
        }
    }

    /// 前面にいる間に、窓切れ(終了時刻ちょうど)の無応答を受け取っても休止せず、その時刻から窓を取り直して確認を続けます。
    ///
    /// 責務: 前面復帰の後の窓切れの無応答で、`.paused` にならず、窓の終了時刻=受け取った時刻+10分で、次の確認が送られることを確認します(U3 受け入れ条件 6)。
    func testNoResponseAfterWindowEndWhileForegroundRenewsWindow() async throws {
        let harness = try await confirmingHarness()
        harness.useCase.appDidBecomeActive()
        let now = F.date(F.windowSeconds)
        harness.clock.now = now

        harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse))
        try await harness.wait("次の確認か休止") { harness.vehicleResponse.timeouts.count == 2 || harness.isConfirming(.paused) }

        XCTAssertFalse(harness.isConfirming(.paused), "前面では休止しない")
        guard case let .confirmingVehicle(confirmation) = harness.useCase.state else {
            return XCTFail("確認中ではない: \(harness.useCase.state)")
        }
        XCTAssertEqual(confirmation.windowEndsAt, now.addingTimeInterval(F.windowSeconds))
        XCTAssertEqual(confirmation.phase, .probing)
    }

    /// サスペンド中に窓が切れ、前面復帰が確認の結果より先に届いても、休止せず窓を取り直して確認を続けます。
    ///
    /// 責務: 窓切れ後の前面復帰で窓が復帰時刻から取り直され、遅れて届いた無応答でも休止しないことを確認します(U3 受け入れ条件 5b・6)。
    func testForegroundBeforeLateResultAfterSuspensionKeepsConfirming() async throws {
        let harness = try await confirmingHarness()
        let resumedAt = F.date(F.windowSeconds + 120)
        harness.clock.now = resumedAt

        harness.useCase.appDidBecomeActive()
        guard case let .confirmingVehicle(renewed) = harness.useCase.state else {
            return XCTFail("確認中ではない: \(harness.useCase.state)")
        }
        XCTAssertEqual(renewed.windowEndsAt, resumedAt.addingTimeInterval(F.windowSeconds))
        harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse))
        try await harness.wait("次の確認か休止") { harness.vehicleResponse.timeouts.count == 2 || harness.isConfirming(.paused) }

        XCTAssertFalse(harness.isConfirming(.paused), "遅れて届いた結果で休止しない")
    }
}
