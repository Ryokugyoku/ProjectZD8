import Foundation
import XCTest

/// 非同期の処理を始め、期限(既定2秒)つきで結果を待つ補助です。期限を超えたら処理を取り消して `XCTFail` します。
@MainActor
final class TestBoundedAsyncRun<Value: Sendable> {
    /// 結果の受け渡し箱です。
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Result<Value, any Error>?
        var value: Result<Value, any Error>? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    private let task: Task<Result<Value, any Error>, Never>

    /// 処理を開始します。
    ///
    /// 責務: 処理を1つの Task で動かし、成功と失敗を `Result` にまとめます。
    init(_ operation: @escaping @Sendable () async throws -> Value) {
        task = Task {
            do { return .success(try await operation()) } catch { return .failure(error) }
        }
    }

    /// 処理を取り消します。
    func cancel() {
        task.cancel()
    }

    /// 期限つきで結果を待ちます。
    ///
    /// 責務: 期限内に終われば結果を返し、超えたら取り消して `XCTFail` し `nil` を返します。
    func result(on testCase: XCTestCase, seconds: TimeInterval = 2,
                file: StaticString = #filePath, line: UInt = #line) async -> Result<Value, any Error>? {
        let box = Box()
        let done = testCase.expectation(description: "bounded async run")
        let task = task
        Task.detached {
            box.value = await task.value
            done.fulfill()
        }
        await testCase.fulfillment(of: [done], timeout: seconds)
        guard let value = box.value else {
            task.cancel()
            XCTFail("期限(\(seconds)秒)内に終わりませんでした", file: file, line: line)
            return nil
        }
        return value
    }

    /// 期限つきで成功の値を待ちます。失敗や期限切れは `XCTFail` して `nil` を返します。
    func value(on testCase: XCTestCase, seconds: TimeInterval = 2,
               file: StaticString = #filePath, line: UInt = #line) async -> Value? {
        guard let outcome = await result(on: testCase, seconds: seconds, file: file, line: line) else { return nil }
        switch outcome {
        case .success(let value): return value
        case .failure(let error):
            XCTFail("成功のはずが失敗しました: \(error)", file: file, line: line)
            return nil
        }
    }

    /// 期限つきで失敗の内容を待ちます。成功や期限切れは `XCTFail` して `nil` を返します。
    func failure(on testCase: XCTestCase, seconds: TimeInterval = 2,
                 file: StaticString = #filePath, line: UInt = #line) async -> (any Error)? {
        guard let outcome = await result(on: testCase, seconds: seconds, file: file, line: line) else { return nil }
        switch outcome {
        case .success:
            XCTFail("失敗のはずが成功しました", file: file, line: line)
            return nil
        case .failure(let error): return error
        }
    }
}
