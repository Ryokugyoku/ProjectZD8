import XCTest
@testable import ProjectZD8

/// 取得方式の判断が示す方式と再試行可否を検証します。
@MainActor
final class OBDAcquisitionModeDecisionTests: XCTestCase {
    /// 判断ごとの取得方式を確認します。
    ///
    /// 責務: 4種の判断が`mode`へ期待どおり対応することを確認します。
    func testMode() {
        XCTAssertEqual(OBDAcquisitionModeDecision.canMonitorUnfiltered.mode, .canMonitor)
        XCTAssertEqual(OBDAcquisitionModeDecision.canMonitorFiltered.mode, .canMonitor)
        XCTAssertEqual(OBDAcquisitionModeDecision.pidPolling.mode, .pidPolling)
        XCTAssertNil(OBDAcquisitionModeDecision.undetermined.mode)
    }

    /// 再試行可否を確認します。
    ///
    /// 責務: undeterminedだけが再試行可能であることを確認します。
    func testIsRetryable() {
        XCTAssertTrue(OBDAcquisitionModeDecision.undetermined.isRetryable)
        XCTAssertFalse(OBDAcquisitionModeDecision.canMonitorUnfiltered.isRetryable)
        XCTAssertFalse(OBDAcquisitionModeDecision.canMonitorFiltered.isRetryable)
        XCTAssertFalse(OBDAcquisitionModeDecision.pidPolling.isRetryable)
    }
}
