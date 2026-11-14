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
    /// 責務: 処理を別Taskで実行し、1ミリ秒ごとの確認を上限時間ぶんだけ行って完了を判定します。
    /// 上限を超えたらTaskを取り消して `false` を返し、処理が取消に応じなくても待ち続けません。
    /// - Parameters:
    ///   - limit: 上限時間。
    ///   - operation: 確かめる処理。
    /// - Returns: 上限内に戻った場合は `true`。
    /// - Throws: 処理が失敗した場合のエラー。
    private func returnsWithin(_ limit: Duration, _ operation: @escaping @Sendable () async throws -> Void) async throws -> Bool {
        let flag = DeadlineWaiterCompletionFlag()
        let task = Task {
            do {
                try await operation()
                flag.finish(with: nil)
            } catch {
                flag.finish(with: error)
            }
        }
        let polls = Int(limit.components.seconds) * 1_000
        for _ in 0..<polls where !flag.isFinished {
            try? await Task.sleep(for: .milliseconds(1))
        }
        guard flag.isFinished else {
            task.cancel()
            return false
        }
        if let error = flag.error { throw error }
        return true
    }
}
