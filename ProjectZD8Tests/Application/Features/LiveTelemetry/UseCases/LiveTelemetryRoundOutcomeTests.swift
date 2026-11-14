import XCTest
@testable import ProjectZD8

/// 1周回の要求結果の集計と、周回後に取得を終える理由の判定を検証します。
final class LiveTelemetryRoundOutcomeTests: XCTestCase {
    /// 正応答が1件でもあれば取得を続け、正応答の要求を順に保持します。
    ///
    /// 責務: 正応答と他の結果が混ざった周回で終了理由が無く、正応答の要求だけが残ることを確認します。
    func testAnyRespondedRequestContinuesAcquisition() {
        var outcome = LiveTelemetryRoundOutcome()
        outcome.add(.timedOut, for: request(0x04))
        outcome.add(.responded([1]), for: request(0x0C))
        outcome.add(.transportFailure, for: request(0x0D))
        outcome.add(.responded([2]), for: request(0x11))

        XCTAssertNil(outcome.termination)
        XCTAssertEqual(outcome.respondedRequests, [request(0x0C), request(0x11)])
    }

    /// 正応答0件で通信失敗があれば接続断です。
    ///
    /// 責務: 通信境界の喪失を含む無応答周回を `connectionLost` へ変換することを確認します。
    func testNoResponseWithTransportFailureIsConnectionLost() {
        var outcome = LiveTelemetryRoundOutcome()
        outcome.add(.timedOut, for: request(0x04))
        outcome.add(.transportFailure, for: request(0x0C))

        XCTAssertEqual(outcome.termination, .connectionLost)
    }

    /// 正応答0件で通信失敗が無ければ無応答です。
    ///
    /// 責務: タイムアウト・非対応・未分類だけの周回と空の周回を `noVehicleResponse` へ変換することを確認します。
    func testNoResponseWithoutTransportFailureIsNoVehicleResponse() {
        let cases: [[OBDPIDRequestTransportOutcome]] = [[], [.timedOut], [.unsupported], [.unclassifiedResponse], [.timedOut, .unsupported]]
        for outcomes in cases {
            var outcome = LiveTelemetryRoundOutcome()
            for (index, result) in outcomes.enumerated() { outcome.add(result, for: request(UInt8(index))) }

            XCTAssertEqual(outcome.termination, .noVehicleResponse, "\(outcomes)")
            XCTAssertEqual(outcome.respondedRequests, [])
        }
    }

    /// 取消があれば、正応答の有無にかかわらず停止です。
    ///
    /// 責務: 取消を他の判定より優先して `stopped` へ変換することを確認します。
    func testCancellationIsStoppedEvenWithResponses() {
        var withResponse = LiveTelemetryRoundOutcome()
        withResponse.add(.responded([1]), for: request(0x0C))
        withResponse.add(.cancelled, for: request(0x0D))
        var onlyCancelled = LiveTelemetryRoundOutcome()
        onlyCancelled.add(.cancelled, for: request(0x0C))

        XCTAssertEqual(withResponse.termination, .stopped)
        XCTAssertEqual(onlyCancelled.termination, .stopped)
    }

    /// Service 01 の要求を生成します。
    ///
    /// 責務: PID番号を要求へ変換します。
    /// - Parameter pid: PID番号。
    /// - Returns: 要求。
    private func request(_ pid: UInt8) -> OBDPIDRequest {
        OBDPIDRequest(service: 0x01, pid: pid)
    }
}
