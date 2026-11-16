import XCTest
@testable import ProjectZD8

/// `LiveTelemetryRecoveryAttempt.isVehicleOffEvidence(for:)` を、結果と途切れの原因の全組み合わせで検証します。
///
/// 仕様: アダプターは応答するが車両が無応答(`vehicleSilent`)で、原因が応答途絶(`responseStall`)のときだけエンジン停止の根拠です。
final class LiveTelemetryRecoveryAttemptTests: XCTestCase {
    /// 全6組み合わせのうち、`vehicleSilent` と `responseStall` だけが根拠になります。
    ///
    /// 責務: 結果3種 × 原因2種の期待値をリテラルの表で確認します。
    func testEvidenceForEveryCombination() {
        let table: [(LiveTelemetryRecoveryAttempt, LiveTelemetryInterruptionCause, Bool)] = [
            (.resumed, .responseStall, false),
            (.resumed, .linkLost, false),
            (.adapterFailed, .responseStall, false),
            (.adapterFailed, .linkLost, false),
            (.vehicleSilent, .responseStall, true),
            (.vehicleSilent, .linkLost, false),
        ]
        for (attempt, cause, expected) in table {
            XCTAssertEqual(attempt.isVehicleOffEvidence(for: cause), expected, "\(attempt) / \(cause)")
        }
    }
}
