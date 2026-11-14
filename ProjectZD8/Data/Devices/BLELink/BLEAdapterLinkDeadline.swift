#if os(iOS) || os(macOS)
/// 注入された待機手段で1件の期限を管理し、再設定・キャンセルされていなければ期限切れを通知します。
@MainActor
final class BLEAdapterLinkDeadline {
    /// 指定時間だけ待つ処理です。キャンセル時は throw するか戻ります。テストは実時間を待たない実装を注入します。
    typealias Sleep = @Sendable (Duration) async throws -> Void

    /// 期限までの待機に使う処理です。
    private let sleep: Sleep
    /// 現在の期限を待つタスクです。
    private var task: Task<Void, Never>?
    /// 再設定・キャンセルのたびに進む世代です。古い期限の通知を捨てるために使います。
    private var generation = 0

    /// 待機手段を固定して生成します。
    ///
    /// 責務: 期限待ちに使う待機処理を保持します。
    /// - Parameter sleep: 指定時間待つ処理。既定は `Task.sleep(for:)`。
    init(sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// 期限が設定されているかどうかです。
    var isArmed: Bool { task != nil }

    /// 既存の期限を捨てて新しい期限を設定します。
    ///
    /// 責務: 1件の期限待ちを開始し、同じ世代のまま待機が終わった時だけ `onExpire` を呼びます。
    /// - Parameters:
    ///   - duration: 期限までの時間。
    ///   - onExpire: 期限切れ時の処理。
    func arm(after duration: Duration, onExpire: @escaping @MainActor () -> Void) {
        cancel()
        let armedGeneration = generation
        let sleep = sleep
        task = Task { [weak self] in
            do {
                try await sleep(duration)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.generation == armedGeneration else { return }
            self.task = nil
            onExpire()
        }
    }

    /// 設定中の期限を捨てます。
    ///
    /// 責務: 待機タスクをキャンセルし、世代を進めて遅れて届く期限切れを無効にします。
    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
    }
}
#endif
