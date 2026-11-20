import Foundation

/// 「更新を確認」で配布の一覧を確かめた状態です。
///
/// 画面を開いただけでは確かめません(押した時だけ通信します)。
nonisolated enum RoadRegulationCatalogCheckStatus: Equatable, Sendable {
    /// まだ確かめていない。
    case notChecked
    /// 確かめている途中。
    case checking
    /// 確かめた。値は確かめた時刻と一覧です。
    case checked(at: Date, catalog: RoadRegulationCatalog)
    /// 確かめられなかった。値は失敗の種類です。
    case failed(RoadRegulationImportError)

    /// 確かめた一覧。確かめていなければ `nil`。
    var catalog: RoadRegulationCatalog? {
        guard case let .checked(_, catalog) = self else { return nil }
        return catalog
    }
}
