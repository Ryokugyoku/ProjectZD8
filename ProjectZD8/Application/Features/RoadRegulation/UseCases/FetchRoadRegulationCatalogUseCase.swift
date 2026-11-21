import Foundation

/// 交通規制データの配布の一覧を取得するユースケースです(「更新を確認」を押した時だけ呼びます)。
nonisolated struct FetchRoadRegulationCatalogUseCase: Sendable {
    /// 一覧の取得元。
    private let source: any RoadRegulationSourcePort
    /// 失敗の分類。
    private let classifier = RoadRegulationImportErrorClassifier()

    /// 取得元を受け取ります。
    ///
    /// 責務: 一覧の取得元を保持します。
    /// - Parameter source: 一覧の取得元。
    init(source: any RoadRegulationSourcePort) {
        self.source = source
    }

    /// 一覧を取得します。
    ///
    /// 責務: メインスレッドの外で取得元を呼び、想定外の失敗を `catalogUnavailable` にします。
    /// - Returns: 配布の一覧。
    /// - Throws: `catalogUnavailable` / `catalogFormatChanged` などの取り込みのエラーか `CancellationError`。
    @concurrent
    func execute() async throws -> RoadRegulationCatalog {
        do {
            return try await source.currentCatalog()
        } catch {
            throw classifier.classified(error, fallback: .catalogUnavailable)
        }
    }
}
