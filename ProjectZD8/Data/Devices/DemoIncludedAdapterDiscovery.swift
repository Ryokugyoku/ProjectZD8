/// 実デバイス探索へ指定されたデモ候補一覧を追加します。
@MainActor
struct DemoIncludedAdapterDiscovery: AdapterDiscoveryPort {
    /// OS由来候補を返す探索境界です。
    private let wrapped: any AdapterDiscoveryPort
    /// 実探索結果へ追加するデモ候補一覧です。
    private let demoCandidates: [DiscoveredAdapter]

    /// 実探索境界と追加対象デモ候補一覧を保持して生成します。
    ///
    /// 責務: 1件の実探索境界を指定接続方式のデモ候補一覧追加処理へ固定します。
    /// - Parameters:
    ///   - wrapped: OS由来候補を取得する探索境界。
    ///   - demoCandidates: 一致する接続方式へ常時追加するデモ候補一覧。
    init(wrapping wrapped: any AdapterDiscoveryPort, demoCandidates: [DiscoveredAdapter]) {
        self.wrapped = wrapped
        self.demoCandidates = demoCandidates
    }

    /// 一致する接続方式の探索へデモ候補を追加します。
    ///
    /// 責務: 1回の探索結果を指定接続方式だけデモ候補一覧付き結果へ変換します。
    /// - Parameter mode: 探索対象の物理接続方式。
    /// - Returns: OS由来候補と重複しないデモ候補一覧。実探索失敗時も一致方式ならデモ候補だけを返します。
    /// - Throws: デモ対象外の接続方式で実探索境界が通知した探索エラー。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        let matchingCandidates = demoCandidates.filter { $0.transportMode == mode }
        guard !matchingCandidates.isEmpty else {
            return try await wrapped.discoverAdapters(for: mode)
        }
        do {
            let discovered = try await wrapped.discoverAdapters(for: mode)
            let demoIDs = Set(matchingCandidates.map(\.id))
            return discovered.filter { !demoIDs.contains($0.id) } + matchingCandidates
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return matchingCandidates
        }
    }
}
