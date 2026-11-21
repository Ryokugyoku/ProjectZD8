@testable import ProjectZD8

/// 位置の取得元の fake です。流れを作った回数と流れの終了回数を数え、テストから手動で位置を流せます。
@MainActor
final class LocationUpdateSourceFake: LocationUpdateSourcePort {
    /// `makeUpdates()` が呼ばれた回数です。
    private(set) var makeUpdatesCallCount = 0
    /// 作った流れの終了(取消・自然終了の両方)を数える計数器です。
    private let terminations = LocationStreamTerminationCounter()
    /// 作った流れの送出口です(作成順)。
    private var continuations: [AsyncStream<LocationUpdateEvent>.Continuation] = []

    /// 流れがない状態で生成します。
    ///
    /// 責務: 呼出回数 0 の fake を構築します。
    init() {}

    /// 作った流れが終了した回数です。取得が止まった回数を表します。
    var terminationCount: Int {
        terminations.count
    }

    /// 位置の流れを作ります。
    ///
    /// 責務: 呼出回数を数え、終了を数える新しい流れを返します。
    /// - Returns: テストから手動で送出できる位置の流れ。
    func makeUpdates() -> AsyncStream<LocationUpdateEvent> {
        makeUpdatesCallCount += 1
        let (stream, continuation) = AsyncStream.makeStream(of: LocationUpdateEvent.self)
        let terminations = terminations
        continuation.onTermination = { _ in terminations.increment() }
        continuations.append(continuation)
        return stream
    }

    /// 最後に作った流れへ1件流します。
    ///
    /// 責務: 最新の流れへ事象を送出します。流れが無ければ何もしません。
    /// - Parameter event: 流す事象。
    func yield(_ event: LocationUpdateEvent) {
        continuations.last?.yield(event)
    }

    /// 最後に作った流れを取得元の側から終えます。
    ///
    /// 責務: 最新の流れを自然終了させます。
    func finish() {
        continuations.last?.finish()
    }

    /// 作ったすべての流れを終えます。
    ///
    /// 責務: テストの後始末として、残っている流れの消費者を確実に終わらせます。
    func finishAll() {
        continuations.forEach { $0.finish() }
    }
}
