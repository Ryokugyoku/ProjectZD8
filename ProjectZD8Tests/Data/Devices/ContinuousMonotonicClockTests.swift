import XCTest
@testable import ProjectZD8

/// 本番の単調時計が減少しないことを検証します。
final class ContinuousMonotonicClockTests: XCTestCase {
    /// 連続して読んだ値が一度も減りません。
    ///
    /// 責務: 固定1000回の連続読み取りで各値が直前以上であることを確認します。
    func testConsecutiveReadsNeverDecrease() {
        let clock = ContinuousMonotonicClock()
        var previous = clock.nowNanoseconds()
        for _ in 0..<1000 {
            let current = clock.nowNanoseconds()
            XCTAssertGreaterThanOrEqual(current, previous)
            previous = current
        }
    }
}
