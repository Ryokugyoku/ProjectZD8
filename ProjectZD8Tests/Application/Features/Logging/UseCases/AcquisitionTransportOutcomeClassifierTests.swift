import XCTest
@testable import ProjectZD8

/// Transport観測の分類と、要求結果からのbatch失敗の集約を検証します。
final class AcquisitionTransportOutcomeClassifierTests: XCTestCase {
    /// 6種類のTransport観測を、取得証跡の分類と理由コードへ変換します。
    ///
    /// 責務: 正応答は理由なし、それ以外は固有の理由コードになることを確認します。
    func testClassifyEachOutcome() {
        let classifier = AcquisitionTransportOutcomeClassifier()
        let cases: [(OBDPIDRequestTransportOutcome, PIDRequestTransportOutcome, String?)] = [
            (.responded([1]), .responded, nil),
            (.unsupported, .unsupported, "explicit_unsupported"),
            (.timedOut, .timedOut, "response_timeout"),
            (.cancelled, .cancelled, "explicit_cancellation"),
            (.transportFailure, .transportFailure, "transport_boundary_lost"),
            (.unclassifiedResponse, .unclassifiedResponse, "unclassified_transport_result")
        ]
        for (input, outcome, reason) in cases {
            let classified = classifier.classify(input)

            XCTAssertEqual(classified.transportOutcome, outcome, "\(input)")
            XCTAssertEqual(classified.reasonCode, reason, "\(input)")
        }
    }

    /// batch失敗は 取消 > 通信不能(通信失敗・タイムアウト) > 未分類 の順に優先し、該当が無ければ無しです。
    ///
    /// 責務: 優先順位と、正応答・非対応だけ・空の場合に失敗が無いことを確認します。
    func testBatchFailurePrecedence() {
        let classifier = AcquisitionTransportOutcomeClassifier()
        let cases: [([PIDRequestTransportOutcome], AcquisitionBatchFailure?)] = [
            ([.timedOut, .cancelled, .unclassifiedResponse], .cancelled),
            ([.unclassifiedResponse, .transportFailure], .transportUnavailable),
            ([.unclassifiedResponse, .timedOut], .transportUnavailable),
            ([.responded, .unclassifiedResponse], .unclassifiedResult),
            ([.responded, .unsupported], nil),
            ([], nil)
        ]
        for (outcomes, expected) in cases {
            XCTAssertEqual(classifier.batchFailure(for: outcomes), expected, "\(outcomes)")
        }
    }
}
