import Foundation

/// 選択された接続方式で利用可能なアダプター候補を読み込むユースケースです。
@MainActor
struct DiscoverAdaptersUseCase {
    /// システム固有の探索処理を隠蔽するポートです。
    private let discoveryPort: any AdapterDiscoveryPort

    /// アダプター探索ポートを注入してユースケースを生成します。
    ///
    /// 責務: アダプター探索ユースケースへ単一の探索境界を結び付けます。
    /// - Parameter discoveryPort: システム固有の探索処理を提供するポート。
    init(discoveryPort: any AdapterDiscoveryPort) {
        self.discoveryPort = discoveryPort
    }

    /// 指定された接続方式で現在選択できる候補を取得します。
    ///
    /// 責務: 1件の接続方式指定を重複のない選択前候補一覧へ変換します。
    /// - Parameter mode: 探索対象の物理接続方式。
    /// - Returns: 表示名順に整列した重複のないアダプター候補。
    /// - Throws: システムのデバイス情報へアクセスできない場合の探索エラー。
    func execute(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        let adapters = try await discoveryPort.discoverAdapters(for: mode)
        let uniqueAdapters = Dictionary(
            adapters.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return uniqueAdapters.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
