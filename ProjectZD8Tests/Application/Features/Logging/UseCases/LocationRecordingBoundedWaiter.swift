import Foundation
import XCTest

/// 走行ルート記録の非同期の結果を期限つきで待ち、期限を超えたら明示的に失敗させる待機手段です。
///
/// `LiveTelemetryBoundedWaiter` と同じ作りで、期限は2秒です。
@MainActor
enum LocationRecordingBoundedWaiter {
    /// 待つ時間の上限です。
    static let timeout: Duration = .seconds(2)
    /// 1回の確認の間に待つ時間です。
    static let pollInterval: Duration = .milliseconds(2)
    /// 確認回数の上限です(眠りが伸びても回数で必ず止まります)。
    static let maximumPolls = 1_000

    /// 条件が成り立つまで期限つきで待ちます。
    ///
    /// 責務: 期限と回数の上限の内で条件を確かめ、成り立たなければ `XCTFail` して `false` を返します。
    /// - Parameters:
    ///   - description: 失敗時に出す待機内容。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - condition: 待つ条件。
    /// - Returns: 期限内に成り立てば `true`。
    @discardableResult
    static func waitUntil(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        for _ in 0..<maximumPolls where ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: pollInterval)
        }
        if condition() { return true }
        XCTFail("期限(2秒)内に成り立ちませんでした: \(description)", file: file, line: line)
        return false
    }

    /// 起きてはいけない非同期処理が走り得る時間だけ待ちます。
    ///
    /// 責務: 否定の確認の前に、固定回数だけ他のタスクへ実行機会を渡します。
    /// - Parameter polls: 待つ回数。
    static func settle(polls: Int = 25) async {
        for _ in 0..<polls {
            await Task.yield()
            try? await Task.sleep(for: pollInterval)
        }
    }
}
