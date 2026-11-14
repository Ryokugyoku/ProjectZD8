import XCTest
@testable import ProjectZD8

/// 3分の猶予判定の境界を検証します。
final class AcquisitionGracePeriodPolicyTests: XCTestCase {
    /// 仕様の猶予3分をナノ秒で表した値です。
    private let threeMinutes: UInt64 = 180 * 1_000_000_000

    /// 経過0は続行します。
    ///
    /// 責務: 一時停止直後が続行になることを確認します。
    func testZeroElapsedContinues() {
        XCTAssertEqual(AcquisitionGracePeriodPolicy().decision(elapsedSincePauseNanoseconds: 0), .continueWaiting)
    }

    /// 3分より1ns短い経過は続行します。
    ///
    /// 責務: 猶予内の上端が続行になることを確認します。
    func testJustBelowGraceContinues() {
        let decision = AcquisitionGracePeriodPolicy().decision(elapsedSincePauseNanoseconds: threeMinutes - 1)
        XCTAssertEqual(decision, .continueWaiting)
    }

    /// ちょうど3分は続行します。
    ///
    /// 責務: 猶予ちょうどが続行になることを確認します。
    func testExactlyGraceContinues() {
        XCTAssertEqual(AcquisitionGracePeriodPolicy().decision(elapsedSincePauseNanoseconds: threeMinutes), .continueWaiting)
    }

    /// 3分より1ns長い経過は終了します。
    ///
    /// 責務: 猶予超過が終了になることを確認します。
    func testJustAboveGraceTerminates() {
        let decision = AcquisitionGracePeriodPolicy().decision(elapsedSincePauseNanoseconds: threeMinutes + 1)
        XCTAssertEqual(decision, .terminate)
    }
}
