import Foundation
import XCTest

/// 非同期に進む取得ループと表示モデルを回数上限付きで待ち、上限を超えたら明示的に失敗させる待機手段です。
///
/// `BLEBoundedWaiter` と同じ作りを LiveTelemetry のテスト側に置いたものです。
@MainActor
enum LiveTelemetryBoundedWaiter {
    /// 1回の確認の間に待つ時間です。
    static let pollInterval: Duration = .milliseconds(2)
    /// 確認回数の上限です(約5秒)。
    static let maximumPolls = 2_500

    /// 条件が成り立つまで回数上限付きで待ちます。
    ///
    /// 責務: 条件を最大 `maximumPolls` 回確認し、成り立たなければ `XCTFail` して `false` を返します。
    /// - Parameters:
    ///   - description: 失敗時に出す待機内容。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - condition: 待つ条件。
    /// - Returns: 上限内に成り立てば `true`。
    @discardableResult
    static func waitUntil(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () async -> Bool
    ) async -> Bool {
        for _ in 0..<maximumPolls {
            if await condition() { return true }
            try? await Task.sleep(for: pollInterval)
        }
        if await condition() { return true }
        XCTFail("上限内に成り立ちませんでした: \(description)", file: file, line: line)
        return false
    }

    /// 非同期処理を別Taskで実行し、上限内に終われば結果を返します。
    ///
    /// 責務: 処理の終了を回数上限付きで待ち、上限を超えたら `XCTFail` して処理のTaskを取り消し、`nil` を返します。
    /// 処理が取消に応じなくても、テストは待ち続けません。
    /// - Parameters:
    ///   - description: 失敗時に出す待機内容。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - operation: 実行する処理。
    /// - Returns: 上限内に終わった場合は処理の結果。
    static func value<Value: Sendable>(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        of operation: @escaping @Sendable () async -> Value
    ) async -> Value? {
        let box = LiveTelemetryAsyncResultBox<Value>()
        let task = Task { box.set(await operation()) }
        guard await waitUntil(description, file: file, line: line, condition: { box.isSet }) else {
            task.cancel()
            return nil
        }
        return box.value
    }

    /// 起きてはいけない非同期処理が走り得る時間だけ待ちます。
    ///
    /// 責務: 否定の確認の前に、固定回数だけ他のタスクへ実行機会を渡します。
    /// - Parameter polls: 待つ回数。
    static func settle(polls: Int = 50) async {
        for _ in 0..<polls {
            await Task.yield()
            try? await Task.sleep(for: pollInterval)
        }
    }
}
