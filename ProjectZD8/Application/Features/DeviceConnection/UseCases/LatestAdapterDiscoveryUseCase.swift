/// 最新要求だけを有効にするアダプター探索ライフサイクルを調整します。
@MainActor
final class LatestAdapterDiscoveryUseCase {
    /// 1回の候補取得を実行する探索ユースケースです。
    private let discoverAdapters: DiscoverAdaptersUseCase

    /// 現在実行中の探索タスクです。
    private var discoveryTask: Task<Void, Never>?

    /// キャンセルへ即応しない古い完了も拒否する探索世代です。
    private var discoveryGeneration: UInt = 0

    /// 単発探索ユースケースを注入して最新探索ユースケースを生成します。
    ///
    /// 責務: 最新探索ライフサイクルを1件の候補取得ユースケースへ結び付けます。
    /// - Parameter discoverAdapters: 接続方式ごとの候補を取得する単発ユースケース。
    init(discoverAdapters: DiscoverAdaptersUseCase) {
        self.discoverAdapters = discoverAdapters
    }

    /// 以前の要求を無効化して指定方式の探索を開始します。
    ///
    /// 責務: 1件の最新探索要求だけを完了通知へ変換します。
    /// - Parameters:
    ///   - mode: 探索対象の物理接続方式。
    ///   - receive: 最新要求が完了した場合だけ呼び出す結果通知。
    func start(
        for mode: AdapterTransportMode,
        receive: @escaping @MainActor (AdapterDiscoveryOutcome) -> Void
    ) {
        invalidateCurrentDiscovery()
        let requestedGeneration = discoveryGeneration

        discoveryTask = Task { [weak self] in
            guard let self else { return }
            let outcome: AdapterDiscoveryOutcome
            do {
                outcome = .discovered(try await discoverAdapters.execute(for: mode))
            } catch is CancellationError {
                return
            } catch let error as AdapterDiscoveryError {
                outcome = .unavailable(error)
            } catch {
                outcome = .failed
            }

            guard acceptsResult(for: requestedGeneration) else { return }
            discoveryTask = nil
            receive(outcome)
        }
    }

    /// 現在の探索を終了して以後の完了通知を無効化します。
    ///
    /// 責務: 進行中の探索タスクとその世代に属する結果を無効化します。
    func cancel() {
        invalidateCurrentDiscovery()
    }

    /// 完了した探索が現在の最新要求かを判定します。
    ///
    /// 責務: 1件の完了結果を現在の探索世代と照合します。
    /// - Parameter generation: 探索開始時に記録した世代。
    /// - Returns: 現在の完了通知へ反映してよい場合は `true`。
    private func acceptsResult(for generation: UInt) -> Bool {
        !Task.isCancelled && discoveryGeneration == generation
    }

    /// 現在の探索タスクと世代を無効化します。
    ///
    /// 責務: 次の探索または終了後に古い結果が通知されない境界を確立します。
    private func invalidateCurrentDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        discoveryGeneration &+= 1
    }
}
