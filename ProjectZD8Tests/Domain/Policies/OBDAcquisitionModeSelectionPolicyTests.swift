import XCTest
@testable import ProjectZD8

/// ATMA試行結果から取得方式への判断を検証します。
@MainActor
final class OBDAcquisitionModeSelectionPolicyTests: XCTestCase {
    /// 6種の試行結果すべての判断を確認します。
    ///
    /// 責務: 全入力が仕様どおりの判断になることを確認します。
    func testDecisionForEveryOutcome() {
        let policy = OBDAcquisitionModeSelectionPolicy()
        XCTAssertEqual(policy.decide(for: .framesReceived), .canMonitorUnfiltered)
        XCTAssertEqual(policy.decide(for: .bufferFull), .canMonitorFiltered)
        XCTAssertEqual(policy.decide(for: .unsupported), .pidPolling)
        XCTAssertEqual(policy.decide(for: .busError), .pidPolling)
        XCTAssertEqual(policy.decide(for: .silent), .undetermined)
        XCTAssertEqual(policy.decide(for: .stopped), .undetermined)
    }
}
