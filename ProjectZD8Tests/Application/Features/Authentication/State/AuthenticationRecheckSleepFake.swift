import Foundation
@testable import ProjectZD8

/// サインイン確認の再確認の待機を、実時間を待たずテストが `finishOldest()` で終わらせるまで保留する Fake です。
///
/// 待機を呼んだタスクが取り消されたら、その待機は `CancellationError` で直ちに終わります。
/// 保留したまま終えないよう、テストの終了時に `drain()` を呼びます。
@MainActor
final class AuthenticationRecheckSleepFake {
    /// 要求された待ち時間です(要求順)。
    private(set) var requestedDurations: [Duration] = []
    /// 取り消しで終わった待機の位置です。
    private(set) var cancelledIndices: Set<Int> = []
    /// まだ終わっていない待機の継続です(位置ごと)。
    private var continuations: [Int: CheckedContinuation<Void, any Error>] = [:]

    /// 注入する待機処理です。
    var sleep: AuthenticationSessionRecheckScheduler.Sleep {
        { [self] duration in try await self.suspend(for: duration) }
    }

    /// 終わっていない待機の件数です。
    var pendingCount: Int { continuations.count }

    /// 最も古い保留中の待機を終わらせます(待ち時間が過ぎたことにします)。
    ///
    /// 責務: 保留が無ければ何もせず `false` を返します。
    /// - Returns: 待機を終わらせたら `true`。
    @discardableResult
    func finishOldest() -> Bool {
        guard let index = continuations.keys.min() else { return false }
        continuations.removeValue(forKey: index)?.resume()
        return true
    }

    /// 保留中の待機をすべて `CancellationError` で終わらせます。
    ///
    /// 責務: テスト終了後に継続を取り残さないようにします。
    func drain() {
        let pending = continuations
        continuations.removeAll()
        pending.values.forEach { $0.resume(throwing: CancellationError()) }
    }

    /// 待機を記録し、テストが終わらせるか取り消されるまで中断します。
    ///
    /// 責務: 要求を記録して継続を保持し、呼び出し元タスクの取り消しで直ちに `CancellationError` を投げさせます。
    /// - Parameter duration: 要求された待ち時間。
    private func suspend(for duration: Duration) async throws {
        let index = requestedDurations.count
        requestedDurations.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                continuations[index] = continuation
            }
        } onCancel: {
            Task { @MainActor in self.cancel(index) }
        }
    }

    /// 取り消された待機を `CancellationError` で終わらせます。
    ///
    /// 責務: まだ終わっていなければ位置を記録して終わらせます。
    /// - Parameter index: 取り消された待機の位置。
    private func cancel(_ index: Int) {
        guard let continuation = continuations.removeValue(forKey: index) else { return }
        cancelledIndices.insert(index)
        continuation.resume(throwing: CancellationError())
    }
}
