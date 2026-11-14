import XCTest
@testable import ProjectZD8

/// 1周回の要求結果から、正応答を返した要求を集計することを検証します。
final class LiveTelemetryRoundOutcomeTests: XCTestCase {
    /// 正応答の要求だけを周回内の順に保持し、他の結果は保持しません。
    ///
    /// 責務: 6種類の結果のうち正応答だけが残ることを確認します。
    func testKeepsOnlyRespondedRequestsInOrder() {
        var outcome = LiveTelemetryRoundOutcome()
        let results: [(UInt8, OBDPIDRequestTransportOutcome)] = [
            (0x04, .timedOut), (0x0C, .responded([1])), (0x0D, .transportFailure), (0x0F, .unsupported),
            (0x10, .unclassifiedResponse), (0x11, .responded([2])), (0x12, .cancelled)
        ]
        for (pid, result) in results { outcome.add(result, for: OBDPIDRequest(service: 0x01, pid: pid)) }

        XCTAssertEqual(outcome.respondedRequests, [OBDPIDRequest(service: 0x01, pid: 0x0C), OBDPIDRequest(service: 0x01, pid: 0x11)])
        XCTAssertEqual(LiveTelemetryRoundOutcome().respondedRequests, [])
    }
}
