import Foundation
import XCTest
@testable import ProjectZD8

/// 取得ループが応答1件につき次の要求を1件だけ送り、応答が無ければ次を送らないことを検証します。
@MainActor
final class LiveTelemetryAcquisitionLoopTests: XCTestCase {
    /// 各テストのループ部品です。
    private var fixture: LiveTelemetryAcquisitionLoopFixture?

    /// 動いている取得を止めます。
    ///
    /// 責務: テストごとに応答待ちの要求と取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// 正応答1件ごとに次の要求がちょうど1件送られます。
    ///
    /// 責務: 正応答で応答駆動の1対1の送信が成り立つことを確認します。
    func testRespondedResultSendsExactlyOneNextRequest() async {
        await assertOneRequestPerResponse(.responded([7]))
    }

    /// タイムアウト1件ごとに次の要求がちょうど1件送られます。
    ///
    /// 責務: タイムアウトでも応答駆動の1対1の送信が成り立つことを確認します。
    func testTimedOutResultSendsExactlyOneNextRequest() async {
        await assertOneRequestPerResponse(.timedOut)
    }

    /// NO DATA 1件ごとに次の要求がちょうど1件送られます。
    ///
    /// 責務: アダプターがNO DATAを未分類応答として返す場合も1対1の送信が成り立つことを確認します。
    func testNoDataResultSendsExactlyOneNextRequest() async {
        await assertOneRequestPerResponse(.unclassifiedResponse)
    }

    /// 明示非対応1件ごとに次の要求がちょうど1件送られます。
    ///
    /// 責務: 明示非対応でも応答駆動の1対1の送信が成り立つことを確認します。
    func testUnsupportedResultSendsExactlyOneNextRequest() async {
        await assertOneRequestPerResponse(.unsupported)
    }

    /// 応答が無い間は次の要求を送りません。
    ///
    /// 責務: 1件目の要求の応答を解放しない限り、送信済み要求・記録・観測が増えないことを確認します。
    func testNoNextRequestIsSentWithoutResponse() async {
        let fixture = LiveTelemetryAcquisitionLoopFixture()
        self.fixture = fixture
        let collector = await fixture.start(definitions: LiveTelemetryTestDefinitions.standard([0x04, 0x0C, 0x0D]))
        await fixture.waitForSentRequests(1)

        await LiveTelemetryBoundedWaiter.settle(polls: 200)

        XCTAssertEqual(fixture.telemetry.sentRequests, [LiveTelemetryTestDefinitions.request(0x04)])
        XCTAssertEqual(fixture.telemetry.pendingRequest, LiveTelemetryTestDefinitions.request(0x04))
        let recorded = await fixture.recorder?.recordedResults
        XCTAssertEqual(recorded, [])
        XCTAssertTrue(collector.samples.isEmpty)
        XCTAssertNil(collector.termination)
    }

    /// 指定した結果で応答を解放するたびに送信済み要求がちょうど1件増えることを検証します。
    ///
    /// 責務: 初回周回の先頭2件に指定結果、以後に正応答を返し、6回の解放それぞれで送信件数が1件だけ増えることを確認します。
    /// - Parameters:
    ///   - kind: 初回周回の先頭2件に返す結果。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    private func assertOneRequestPerResponse(
        _ kind: OBDPIDRequestTransportOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let fixture = LiveTelemetryAcquisitionLoopFixture()
        self.fixture = fixture
        _ = await fixture.start(definitions: LiveTelemetryTestDefinitions.standard([0x04, 0x0C, 0x0D]))
        await fixture.waitForSentRequests(1, file: file, line: line)
        await LiveTelemetryBoundedWaiter.settle(polls: 20)
        XCTAssertEqual(fixture.telemetry.sentRequests.count, 1, file: file, line: line)
        let outcomes: [OBDPIDRequestTransportOutcome] = [
            kind, kind, .responded([10]), .responded([11]), .responded([12]), .responded([13])
        ]

        for (index, outcome) in outcomes.enumerated() {
            await fixture.telemetry.release(outcome, file: file, line: line)
            await fixture.waitForSentRequests(index + 2, file: file, line: line)
            await LiveTelemetryBoundedWaiter.settle(polls: 20)
            XCTAssertEqual(fixture.telemetry.sentRequests.count, index + 2, "解放 \(index + 1) 回目", file: file, line: line)
            XCTAssertNotNil(fixture.telemetry.pendingRequest, file: file, line: line)
        }
        XCTAssertEqual(fixture.telemetry.requestCountsPerCall, Array(repeating: 1, count: outcomes.count + 1), file: file, line: line)
    }
}
