import XCTest
@testable import ProjectZD8

/// 周回番号・batch番号・取得対象の確定を進める周回の位置を検証します。
final class LiveTelemetryPollingCursorTests: XCTestCase {
    /// 正応答の無い周回は確定せず、周回番号は0のままbatch番号だけ進みます。
    ///
    /// 責務: 確定前の無応答周回の扱いを確認します。
    func testRoundWithoutResponseKeepsBaseRound() {
        var cursor = LiveTelemetryPollingCursor(definitions: LiveTelemetryTestDefinitions.standard([0x0C, 0x0D]))

        XCTAssertNil(cursor.advance(after: LiveTelemetryRoundOutcome()))

        XCTAssertEqual(cursor.tick, 0)
        XCTAssertEqual(cursor.batchOrdinal, 1)
        XCTAssertFalse(cursor.isConfirmed)
        XCTAssertEqual(cursor.targets.map(\.pid), [0x0C, 0x0D])
    }

    /// 最初に正応答のあった周回で、応答したPIDだけを取得対象に確定し、以後は周回番号も進めます。
    ///
    /// 責務: 確定時に返す対象・確定後の進み方・確定済みでは対象を返さないことを確認します。
    func testFirstRespondedRoundConfirmsTargets() {
        var cursor = LiveTelemetryPollingCursor(definitions: LiveTelemetryTestDefinitions.standard([0x0C, 0x0D]))
        var outcome = LiveTelemetryRoundOutcome()
        outcome.add(.timedOut, for: LiveTelemetryTestDefinitions.request(0x0C))
        outcome.add(.responded([1]), for: LiveTelemetryTestDefinitions.request(0x0D))

        let confirmed = cursor.advance(after: outcome)
        let later = cursor.advance(after: LiveTelemetryRoundOutcome())

        XCTAssertEqual(confirmed?.map(\.pid), [0x0D])
        XCTAssertNil(later)
        XCTAssertEqual(cursor.targets.map(\.pid), [0x0D])
        XCTAssertEqual(cursor.tick, 2)
        XCTAssertEqual(cursor.batchOrdinal, 2)
    }

    /// 打ち切った周回はbatch番号を進め、確定後だけ周回番号も進めます。
    ///
    /// 責務: 確定前後の `abandonRound` の進み方を確認します。
    func testAbandonRoundAdvancesBatchAndTickOnlyAfterConfirmation() {
        var cursor = LiveTelemetryPollingCursor(definitions: LiveTelemetryTestDefinitions.standard([0x0C]))
        cursor.abandonRound()
        XCTAssertEqual(cursor.batchOrdinal, 1)
        XCTAssertEqual(cursor.tick, 0)
        var outcome = LiveTelemetryRoundOutcome()
        outcome.add(.responded([1]), for: LiveTelemetryTestDefinitions.request(0x0C))
        _ = cursor.advance(after: outcome)

        cursor.abandonRound()

        XCTAssertEqual(cursor.batchOrdinal, 3)
        XCTAssertEqual(cursor.tick, 2)
    }
}
