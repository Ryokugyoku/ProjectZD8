@testable import ProjectZD8

/// 位置の購読口の fake です。購読回数と各流れの終了回数を数え、テストから手動で位置を流せます。
@MainActor
final class LocationUpdateSubscriptionFake: LocationUpdateSubscriptionPort {
    /// `subscribe()` が呼ばれた回数です。
    private(set) var subscribeCallCount = 0
    /// 購読した流れの終了(取消・自然終了の両方)を数える計数器です。
    private let terminations = LocationStreamTerminationCounter()
    /// 購読した流れの送出口です(購読順)。
    private var continuations: [AsyncStream<LocationUpdateEvent>.Continuation] = []

    /// 購読がない状態で生成します。
    ///
    /// 責務: 購読回数 0 の fake を構築します。
    init() {}

    /// 購読した流れが終了した回数です。購読が取消された回数を表します。
    var terminationCount: Int {
        terminations.count
    }

    /// 終了していない購読の数です。
    var activeSubscriptionCount: Int {
        subscribeCallCount - terminationCount
    }

    /// 位置の流れを購読します。
    ///
    /// 責務: 購読回数を数え、終了を数える新しい流れを返します。
    /// - Returns: テストから手動で送出できる位置の流れ。
    func subscribe() -> AsyncStream<LocationUpdateEvent> {
        subscribeCallCount += 1
        let (stream, continuation) = AsyncStream.makeStream(of: LocationUpdateEvent.self)
        let terminations = terminations
        continuation.onTermination = { _ in terminations.increment() }
        continuations.append(continuation)
        return stream
    }

    /// 最後に購読された流れへ1件流します。
    ///
    /// 責務: 最新の購読へ事象を送出します。購読が無ければ何もしません。
    /// - Parameter event: 流す事象。
    func yield(_ event: LocationUpdateEvent) {
        continuations.last?.yield(event)
    }

    /// 最後に購読された流れを終えます。
    ///
    /// 責務: 最新の購読を自然終了させます。
    func finish() {
        continuations.last?.finish()
    }

    /// 購読されたすべての流れを終えます。
    ///
    /// 責務: テストの後始末として、残っている流れの消費者を確実に終わらせます。
    func finishAll() {
        continuations.forEach { $0.finish() }
    }
}
