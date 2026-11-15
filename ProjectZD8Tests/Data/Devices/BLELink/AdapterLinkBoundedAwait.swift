import Foundation
import XCTest

/// 非同期タスクの完了を回数上限付きで待ち、上限を超えたら明示的に失敗させる待機手段です。
///
/// テスト対象が無期限に待つように壊れても、テストは「停止しない」ではなく「失敗」になります。
@MainActor
enum AdapterLinkBoundedAwait {
    /// タスクの結果を受け取る入れ物です。
    private final class OutcomeBox<Value> {
        /// 完了したタスクの結果です。未完了なら `nil`。
        var outcome: Result<Value, any Error>?
    }

    /// 1回の確認の間に待つ時間です。
    static let pollInterval: Duration = .milliseconds(2)
    /// 確認回数の上限です(約5秒)。
    static let maximumPolls = 2_500

    /// 処理をタスクとして始め、その結果を上限付きで待ちます。
    ///
    /// 責務: 処理を MainActor のタスクで実行し、`outcome(of:_:)` で待ちます。
    /// - Parameters:
    ///   - description: 失敗時に出す待機内容。
    ///   - operation: 実行する処理。
    /// - Returns: 上限内に終われば結果。終わらなければ `nil`(XCTFail 済み)。
    static func run<Value>(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: @escaping @MainActor () async throws -> Value
    ) async -> Result<Value, any Error>? {
        let task = Task { @MainActor in try await operation() }
        return await outcome(of: task, description, file: file, line: line)
    }

    /// 処理を上限付きで待ち、成功した値を返します(製品の async API を直接 await する代わりに使います)。
    ///
    /// 責務: `run(_:operation:)` で待ち、上限内に終われば結果を返すか同じエラーで throw し、終わらなければ XCTFail して throw します。
    /// - Parameters:
    ///   - description: 失敗時に出す待機内容。
    ///   - operation: 実行する処理。
    /// - Returns: 処理の戻り値。
    /// - Throws: 処理のエラー、または上限超過の `AdapterLinkBoundedAwaitTimeout`。
    static func value<Value>(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        guard let outcome = await run(description, file: file, line: line, operation: operation) else {
            throw AdapterLinkBoundedAwaitTimeout(description: description)
        }
        return try outcome.get()
    }

    /// 開始済みタスクの結果を上限付きで待ちます。
    ///
    /// 責務: 最大 `maximumPolls` 回だけ完了を確認し、終わらなければタスクをキャンセルして XCTFail します。
    /// - Parameters:
    ///   - task: 待つタスク。
    ///   - description: 失敗時に出す待機内容。
    /// - Returns: 上限内に終われば結果。終わらなければ `nil`。
    static func outcome<Value>(
        of task: Task<Value, any Error>,
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Result<Value, any Error>? {
        let box = OutcomeBox<Value>()
        Task { @MainActor in box.outcome = await task.result }
        for _ in 0..<maximumPolls {
            if let outcome = box.outcome { return outcome }
            try? await Task.sleep(for: pollInterval)
        }
        if let outcome = box.outcome { return outcome }
        task.cancel()
        XCTFail("上限内に終わりませんでした: \(description)", file: file, line: line)
        return nil
    }

    /// 結果が指定エラーでの失敗であることを確かめます。
    ///
    /// 責務: 成功・別エラー・未完了をすべて失敗として報告します。
    /// - Parameters:
    ///   - outcome: 待った結果。
    ///   - expected: 期待するエラー。
    static func assertFailure<Value, Failure: Error & Equatable>(
        _ outcome: Result<Value, any Error>?,
        _ expected: Failure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let outcome else { return }
        switch outcome {
        case .success(let value):
            XCTFail("\(expected) で失敗するはずが成功しました: \(value)", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error as? Failure, expected, "実際のエラー: \(error)", file: file, line: line)
        }
    }

    /// 結果が成功であることを確かめて値を返します。
    ///
    /// 責務: 失敗・未完了を報告し、成功時だけ値を返します。
    /// - Parameter outcome: 待った結果。
    /// - Returns: 成功した値。失敗・未完了なら `nil`。
    static func successValue<Value>(
        _ outcome: Result<Value, any Error>?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Value? {
        guard let outcome else { return nil }
        switch outcome {
        case .success(let value):
            return value
        case .failure(let error):
            XCTFail("成功するはずが失敗しました: \(error)", file: file, line: line)
            return nil
        }
    }
}
