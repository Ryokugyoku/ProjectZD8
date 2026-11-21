import Foundation

/// 交通規制データの配布の一覧です。
nonisolated struct RoadRegulationCatalog: Equatable, Sendable {
    /// 一覧が示す基準月。読めなければ `nil`。
    let dataMonth: RoadRegulationDataMonth?
    /// 都道府県ごとの ZIP。
    let entries: [RoadRegulationCatalogEntry]

    /// 都道府県の ZIP を返します。
    ///
    /// 責務: 一覧から指定した都道府県の最初の項目を探します。
    /// - Parameter prefecture: 探す都道府県。
    /// - Returns: 一覧に無ければ `nil`。
    func entry(for prefecture: JapanesePrefectureCode) -> RoadRegulationCatalogEntry? {
        entries.first { $0.prefecture == prefecture }
    }
}
