import Foundation
@testable import ProjectZD8

/// 期限待ちを要求された期限ごとに保持し、テストが明示的に解放するまで待たせる期限待ちのフェイクです。
///
/// 実時間では待ちません。取消されたTaskの期限待ちは `CancellationError` で解放します。
/// テスト終了時は `releaseAll()` で残りをすべて解放します。
final class ControlledDeadlineWaiterFake: LiveTelemetryDeadlineWaitPort, @unchecked Sendable {
    /// 保持中の期限待ちです。
    private struct Waiter {
        /// 取消と解放を対応付ける番号です。
        let identifier: Int
        /// 要求された期限です。
        let deadline: UInt64
        /// 解放する continuation です。
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// 保持内容を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した保持中の期限待ちです。
    private var waiters: [Waiter] = []
    /// ロックで保護した要求された期限です。要求順に並びます。
    private var storedRequests: [UInt64] = []
    /// ロックで保護した次の番号です。
    private var nextIdentifier = 0

    /// 空の状態で生成します。
    ///
    /// 責務: 期限待ちを1件も持たないフェイクを構築します。
    init() {}

    /// 保持中の期限です。昇順に並びます。
    var pendingDeadlines: [UInt64] {
        lock.withLock { waiters.map(\.deadline).sorted() }
    }

    /// これまでに要求された期限です。要求順に並びます。
    var requestedDeadlines: [UInt64] {
        lock.withLock { storedRequests }
    }

    /// 期限まで待ちます。
    ///
    /// 責務: 期限待ちを保持し、テストの解放またはTaskの取消まで待ちます。
    /// - Parameter deadlineNanoseconds: 起床する単調時計の値。
    /// - Throws: 取消された場合は `CancellationError`。
    func wait(untilNanoseconds deadlineNanoseconds: UInt64) async throws {
        let identifier = lock.withLock {
            storedRequests.append(deadlineNanoseconds)
            defer { nextIdentifier += 1 }
            return nextIdentifier
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let isCancelled = lock.withLock {
                    if Task.isCancelled { return true }
                    waiters.append(Waiter(identifier: identifier, deadline: deadlineNanoseconds, continuation: continuation))
                    return false
                }
                if isCancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            self.cancel(identifier: identifier)
        }
    }

    /// 指定期限の期限待ちを、期限に達したものとして解放します。
    ///
    /// 責務: 期限が一致する保持中の期限待ちをすべて正常に戻します。
    /// - Parameter deadline: 解放する期限。
    /// - Returns: 解放した件数。
    @discardableResult
    func release(deadline: UInt64) -> Int {
        let released = lock.withLock {
            let matching = waiters.filter { $0.deadline == deadline }
            waiters.removeAll { $0.deadline == deadline }
            return matching
        }
        released.forEach { $0.continuation.resume() }
        return released.count
    }

    /// 指定期限の期限待ちが保持されるまで上限付きで待ちます。
    ///
    /// 責務: 期限待ちの到着を待ち、上限を超えたら失敗させます。
    /// - Parameters:
    ///   - deadline: 待つ期限。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: 到着した場合は `true`。
    @MainActor
    @discardableResult
    func waitForPending(_ deadline: UInt64, file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        await LiveTelemetryBoundedWaiter.waitUntil("期限待ち \(deadline)", file: file, line: line) {
            self.pendingDeadlines.contains(deadline)
        }
    }

    /// 保持中の期限待ちをすべて解放します。
    ///
    /// 責務: テスト終了時に待たせたままのTaskを残さないようにします。
    func releaseAll() {
        let released = lock.withLock {
            defer { waiters.removeAll() }
            return waiters
        }
        released.forEach { $0.continuation.resume() }
    }

    /// 取消されたTaskの期限待ちを解放します。
    ///
    /// 責務: 番号が一致する期限待ちを `CancellationError` で戻します。
    /// - Parameter identifier: 取消された期限待ちの番号。
    private func cancel(identifier: Int) {
        let cancelled = lock.withLock {
            let matching = waiters.filter { $0.identifier == identifier }
            waiters.removeAll { $0.identifier == identifier }
            return matching
        }
        cancelled.forEach { $0.continuation.resume(throwing: CancellationError()) }
    }
}
