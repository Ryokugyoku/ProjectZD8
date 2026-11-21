import Foundation
import XCTest

/// 同期の処理を別スレッドで走らせ、期限(既定30秒)を超えたら明示的に失敗させる実行器です(止まらない実装を「失敗」にするため)。
@MainActor
enum TestBoundedExecution {
    /// 結果の受け渡し箱です。
    private final class Box<T>: @unchecked Sendable {
        /// 結果。完了前は `nil`。
        var value: T?
    }

    /// 責務: 処理を期限つきで実行します。期限を超えたら `XCTFail` して `nil` を返します。
    /// - Parameters:
    ///   - testCase: 待つテスト。
    ///   - seconds: 期限(秒)。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - work: 実行する処理。
    /// - Returns: 処理の結果。期限切れなら `nil`。
    static func run<T: Sendable>(
        on testCase: XCTestCase, seconds: TimeInterval = 30,
        file: StaticString = #filePath, line: UInt = #line,
        _ work: @escaping @Sendable () -> T
    ) -> T? {
        let box = Box<T>()
        let finished = testCase.expectation(description: "bounded work")
        DispatchQueue.global().async {
            box.value = work()
            finished.fulfill()
        }
        let outcome = XCTWaiter().wait(for: [finished], timeout: seconds)
        guard outcome == .completed, let value = box.value else {
            XCTFail("期限(\(seconds)秒)内に終わりませんでした", file: file, line: line)
            return nil
        }
        return value
    }
}
