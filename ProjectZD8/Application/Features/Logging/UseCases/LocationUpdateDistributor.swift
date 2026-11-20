import Foundation

/// 1つの位置の流れを、購読者ごとの流れへ配る役です。
///
/// - 購読者が0→1になったら `source.makeUpdates()` を読み始め、全購読者へ同じ事象を配ります。
/// - 購読者の流れが終了・取消されたら外し、1→0になったら読むのをやめます(取得が止まります)。
/// - source の流れが自分から終わったら、全購読者の流れを終えます。その後の購読では読み直します。
@MainActor
final class LocationUpdateDistributor: LocationUpdateSubscriptionPort {
    /// 位置を取得する唯一の口です。
    private let source: any LocationUpdateSourcePort
    /// 購読者ごとの流れの送り口です。
    private var subscribers: [UUID: AsyncStream<LocationUpdateEvent>.Continuation] = [:]
    /// source の流れを読むタスクです。読んでいなければ `nil`。
    private var readingTask: Task<Void, Never>?
    /// 読み取りの世代です。取消した古い読み取りの終了を、新しい読み取りの終了と取り違えないために使います。
    private var readingGeneration = 0

    /// 現在の購読者数です。
    var subscriberCount: Int {
        subscribers.count
    }

    /// 位置の取得口を注入して生成します。
    ///
    /// 責務: 配る元の流れを作る取得口を1つ固定します。
    /// - Parameter source: 位置を取得する唯一の口。
    init(source: any LocationUpdateSourcePort) {
        self.source = source
    }

    /// 読み取りを止め、残っている購読者の流れを終えます。
    deinit {
        readingTask?.cancel()
        subscribers.values.forEach { $0.finish() }
    }

    /// 位置の流れを購読します。
    ///
    /// 責務: 購読者ごとの流れを作って登録し、最初の購読者なら source の読み取りを始めます。
    /// - Returns: 位置または取得不可の通知の流れ。終了・取消すると購読を外します。
    func subscribe() -> AsyncStream<LocationUpdateEvent> {
        let identifier = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: LocationUpdateEvent.self)
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeSubscriber(identifier)
            }
        }
        subscribers[identifier] = continuation
        startReadingIfNeeded()
        return stream
    }

    /// 購読者を外し、最後の購読者なら読み取りを止めます。
    ///
    /// 責務: 終了・取消された購読者の送り口を外し、購読者が0になったら source の読み取りを取消します。
    /// - Parameter identifier: 外す購読者。
    private func removeSubscriber(_ identifier: UUID) {
        guard subscribers.removeValue(forKey: identifier) != nil else { return }
        if subscribers.isEmpty {
            stopReading()
        }
    }

    /// 読み取りをしていなければ source の流れを読み始めます。
    ///
    /// 責務: 購読者がいて読み取りが無い時だけ、新しい世代で source の流れを1本作って読み始めます。
    private func startReadingIfNeeded() {
        guard readingTask == nil, !subscribers.isEmpty else { return }
        readingGeneration += 1
        let generation = readingGeneration
        let updates = source.makeUpdates()
        readingTask = Task { [weak self] in
            for await event in updates {
                guard let self else { return }
                self.broadcast(event)
            }
            self?.readingDidEnd(generation: generation)
        }
    }

    /// 読み取りを取消します。
    ///
    /// 責務: source の流れを読むタスクを取消して、取得を止めさせます。
    private func stopReading() {
        readingTask?.cancel()
        readingTask = nil
    }

    /// 1件の事象を全購読者へ配ります。
    ///
    /// 責務: 受け取った事象を、登録中のすべての購読者の流れへ同じ順で流します。
    /// - Parameter event: 配る事象。
    private func broadcast(_ event: LocationUpdateEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    /// source の流れが終わった時に、全購読者の流れを終えます。
    ///
    /// 責務: 取消ではなく source が自分から終わった場合だけ、購読者を外して各流れを終えます。
    /// - Parameter generation: 終わった読み取りの世代。
    private func readingDidEnd(generation: Int) {
        guard generation == readingGeneration, readingTask != nil else { return }
        readingTask = nil
        let finishedSubscribers = subscribers.values
        subscribers.removeAll()
        finishedSubscribers.forEach { $0.finish() }
    }
}
