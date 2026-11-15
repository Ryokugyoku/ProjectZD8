import Foundation
import XCTest
@testable import ProjectZD8

/// プロセス復帰時に、最後のcommitからの実時間の経過で続行か終了かを決める方針を検証します。
final class AcquisitionRelaunchPolicyTests: XCTestCase {
    /// 最後にcommitした実時刻です。
    private let lastCommittedAt = Date(timeIntervalSince1970: 10_000)

    /// 経過0とちょうど3分とその直前は続行、直後は終了です。
    ///
    /// 責務: 猶予の境界値を確認します。
    func testGraceBoundaries() {
        let policy = AcquisitionRelaunchPolicy()

        XCTAssertEqual(policy.decision(lastCommittedAt: lastCommittedAt, now: lastCommittedAt), .continueWaiting)
        XCTAssertEqual(policy.decision(lastCommittedAt: lastCommittedAt, now: lastCommittedAt.addingTimeInterval(179.999)), .continueWaiting)
        XCTAssertEqual(policy.decision(lastCommittedAt: lastCommittedAt, now: lastCommittedAt.addingTimeInterval(180)), .continueWaiting)
        XCTAssertEqual(policy.decision(lastCommittedAt: lastCommittedAt, now: lastCommittedAt.addingTimeInterval(180.001)), .terminate)
    }

    /// 現在が最後のcommitより前(時計の逆行)なら終了です。
    ///
    /// 責務: 負の経過を続行と扱わないことを確認します。
    func testBackwardClockTerminates() {
        XCTAssertEqual(AcquisitionRelaunchPolicy().decision(lastCommittedAt: lastCommittedAt, now: lastCommittedAt.addingTimeInterval(-0.001)), .terminate)
    }
}
