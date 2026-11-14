import Foundation
import XCTest
@testable import ProjectZD8

/// 単調時計の期限まで待つ部品が、過去の期限では即座に戻り、数ミリ秒先の期限では上限内に戻ることを検証します。
final class ContinuousMonotonicDeadlineWaiterTests: XCTestCase {
    /// 期限が現在以前なら、待たずに戻ります。
    ///
    /// 責務: 過去と現在ちょうどの期限が上限(1秒)内に戻ることを確認します。
    func testPastOrCurrentDeadlineReturnsImmediately() async throws {
        let clock = ManualMonotonicClock(initialNanoseconds: 5_000_000_000)
        let waiter = ContinuousMonotonicDeadlineWaiter(clock: clock)

        let pastReturned = try await returnsWithin(.seconds(1)) { try await waiter.wait(untilNanoseconds: 1) }
        let currentReturned = try await returnsWithin(.seconds(1)) { try await waiter.wait(untilNanoseconds: 5_000_000_000) }

        XCTAssertTrue(pastReturned)
        XCTAssertTrue(currentReturned)
    }

    /// 数ミリ秒先の期限では、上限(5秒)内に戻ります。
    ///
    /// 責務: 実時間の単調時計で、近い将来の期限まで待って戻ることを確認します。
    func testNearFutureDeadlineReturnsWithinLimit() async throws {
        let clock = ContinuousMonotonicClock()
        let waiter = ContinuousMonotonicDeadlineWaiter(clock: clock)
        let deadline = clock.nowNanoseconds() + 3_000_000

        let returned = try await returnsWithin(.seconds(5)) { try await waiter.wait(untilNanoseconds: deadline) }

        XCTAssertTrue(returned)
        XCTAssertGreaterThanOrEqual(clock.nowNanoseconds(), deadline)
    }

    /// 処理が上限時間内に戻るかを確かめます。
    ///
    /// 責務: 処理と上限時間の待ちを競わせ、先に終わった方で判定し、残りを取り消します。
    /// - Parameters:
    ///   - limit: 上限時間。
    ///   - operation: 確かめる処理。
    /// - Returns: 上限内に戻った場合は `true`。
    /// - Throws: 処理が失敗した場合のエラー。
    private func returnsWithin(_ limit: Duration, _ operation: @escaping @Sendable () async throws -> Void) async throws -> Bool {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await operation()
                return true
            }
            group.addTask {
                try await Task.sleep(for: limit)
                return false
            }
            let first = try await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
