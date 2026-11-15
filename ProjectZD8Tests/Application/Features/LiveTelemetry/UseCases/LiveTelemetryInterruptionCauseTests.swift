import XCTest
@testable import ProjectZD8

/// 途絶の原因から区間の終了理由・欠損の原因・セッションの終了原因への変換を検証します。
final class LiveTelemetryInterruptionCauseTests: XCTestCase {
    /// 応答途絶は responseStall / responseStall / 車両無応答、リンク断は linkLost / linkLost / 接続断です。
    ///
    /// 責務: 2つの原因の3つの変換を確認します。
    func testMappings() {
        XCTAssertEqual(LiveTelemetryInterruptionCause.responseStall.segmentEndReason, .responseStall)
        XCTAssertEqual(LiveTelemetryInterruptionCause.responseStall.gapCause, .responseStall)
        XCTAssertEqual(LiveTelemetryInterruptionCause.responseStall.sessionEndReason, .vehicleNoResponse)
        XCTAssertEqual(LiveTelemetryInterruptionCause.linkLost.segmentEndReason, .linkLost)
        XCTAssertEqual(LiveTelemetryInterruptionCause.linkLost.gapCause, .linkLost)
        XCTAssertEqual(LiveTelemetryInterruptionCause.linkLost.sessionEndReason, .connectionLost)
    }
}
