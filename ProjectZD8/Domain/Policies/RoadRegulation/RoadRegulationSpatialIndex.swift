import Foundation

/// メモリ上の交通規制の集まりを升目で引く索引です。
///
/// 規制の形状が重なる升目ごとに規制を登録し、位置の周辺の升目に登録された規制だけを返します。
/// 升目を求められない(大きすぎる)形状の規制は、取りこぼさないようにどの位置でも候補として返します。
nonisolated struct RoadRegulationSpatialIndex: Sendable {
    /// 升目の計算器です。
    private let grid: RoadRegulationGrid
    /// 行 ID の昇順・重複なしに並べた規制です。
    private let regulations: [RoadRegulation]
    /// 升目ごとの、`regulations` の添字の一覧です。
    private let indicesByCell: [RoadRegulationCellKey: [Int]]
    /// 升目を求められず、どの位置でも候補にする規制の添字です。
    private let unindexedIndices: [Int]

    /// 規制の集まりから索引を作ります。
    ///
    /// 責務: 同じ行 ID の規制を最初の1件にまとめて行 ID の昇順に並べ、形状が重なる升目へ登録します。
    /// - Parameters:
    ///   - regulations: 索引にする規制(順不同。同じ行 ID が重なってもよい)。
    ///   - grid: 升目の計算器。
    init(regulations: [RoadRegulation], grid: RoadRegulationGrid = .init()) {
        var seen = Set<RoadRegulationID>()
        let unique = regulations.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
        var indicesByCell: [RoadRegulationCellKey: [Int]] = [:]
        var unindexed: [Int] = []
        for (index, regulation) in unique.enumerated() {
            guard let cells = grid.cells(covering: regulation.geometry, shape: regulation.kind.expectedShape) else {
                unindexed.append(index)
                continue
            }
            for cell in cells {
                indicesByCell[cell, default: []].append(index)
            }
        }
        self.grid = grid
        self.regulations = unique
        self.indicesByCell = indicesByCell
        self.unindexedIndices = unindexed
    }

    /// 位置の周辺の規制を返します。
    ///
    /// 責務: 位置を中心に半径だけ広げた範囲と重なる升目に登録された規制を、重複を除いて行 ID の昇順で返します。
    /// - Parameters:
    ///   - coordinate: 中心の位置。
    ///   - radiusMeters: 探す半径(m)。負の値と有限でない値は 0 とみなします。
    /// - Returns: 周辺の規制(行 ID の昇順・重複なし)。升目の単位で絞るため、半径の少し外の規制も含み得ます。
    func candidates(around coordinate: GeoCoordinate, radiusMeters: Double) -> [RoadRegulation] {
        var indices = Set(unindexedIndices)
        for cell in grid.cells(around: coordinate, radiusMeters: radiusMeters) {
            indices.formUnion(indicesByCell[cell] ?? [])
        }
        return indices.sorted().map { regulations[$0] }
    }
}
