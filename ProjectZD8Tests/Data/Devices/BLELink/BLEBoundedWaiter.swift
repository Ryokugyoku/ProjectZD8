import Foundation
import XCTest

/// 非同期に進む処理を回数上限付きで待ち、上限を超えたら明示的に失敗させる待機手段です。
@MainActor
enum BLEBoundedWaiter {
    /// 1回の確認の間に待つ時間です。
    static let pollInterval: Duration = .milliseconds(2)
    /// 確認回数の上限です(約2秒)。
    static let maximumPolls = 1_000

    /// 条件が成り立つまで回数上限付きで待ちます。
    ///
    /// 責務: 条件を最大 `maximumPolls` 回確認し、成り立たなければ `XCTFail` して `false` を返します。
    /// - Parameters:
    ///   - description: 失敗時に出す待機内容。
    ///   - condition: 待つ条件。
    /// - Returns: 上限内に成り立てば `true`。
    @discardableResult
    static func waitUntil(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async throws -> Bool {
        for _ in 0..<maximumPolls {
            if condition() { return true }
            try await Task.sleep(for: pollInterval)
        }
        if condition() { return true }
        XCTFail("上限内に成り立ちませんでした: \(description)", file: file, line: line)
        return false
    }

    /// 起きてはいけない非同期処理が走り得る時間だけ待ちます。
    ///
    /// 責務: 否定の確認の前に、固定回数だけ他のタスクへ実行機会を渡します。
    /// - Parameter polls: 待つ回数。
    static func settle(polls: Int = 50) async throws {
        for _ in 0..<polls {
            await Task.yield()
            try await Task.sleep(for: pollInterval)
        }
    }
}
