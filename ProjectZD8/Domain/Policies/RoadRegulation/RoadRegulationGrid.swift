import Foundation

/// 交通規制の検索に使う升目(JIS の2分の1地域メッシュと同じ刻み)を求めます。
///
/// 升目は緯度方向 1/240 度(15″)、経度方向 1/160 度(22.5″)です。
/// row = floor((緯度 + 90) × 240)、column = floor((経度 + 180) × 160)。
nonisolated struct RoadRegulationGrid: Sendable {
    /// 緯度1度あたりの升目の数です。
    static let rowsPerDegree = 240
    /// 経度1度あたりの升目の数です。
    static let columnsPerDegree = 160
    /// 1つの形状に割り当てられる升目の上限です。超える形状は割り当てずに `nil` を返します。
    static let maximumCellsPerGeometry = 10_000
    /// 線分を升目へ割り当てる時に分ける小片の最大の長さ(m)です。
    static let segmentPieceMeters = 200.0
    /// 升目の境目ちょうどとみなす升目単位の許容差です(約0.5 mm)。10進の緯度経度を2進で表した時の誤差を吸収します。
    private static let boundarySnapTolerance = 1e-9

    /// 線分の長さを求める計算器です。
    private let distanceCalculator = GeoDistanceCalculator()

    /// 状態を持たない升目の計算器を作ります。
    ///
    /// 責務: 定数だけで計算する升目の計算器を構築します。
    init() {}

    /// 座標を含む升目を返します。
    ///
    /// 責務: 緯度・経度を升目番号へ直します。境目ちょうどの点は北側・東側の升目にします。
    /// - Parameter coordinate: 調べる座標。
    /// - Returns: 升目の鍵。
    func cell(containing coordinate: GeoCoordinate) -> RoadRegulationCellKey {
        RoadRegulationCellKey(row: Self.row(ofLatitude: coordinate.latitude), column: Self.column(ofLongitude: coordinate.longitude))
    }

    /// 座標を中心に半径 r の外接矩形が重なる升目を返します。
    ///
    /// 責務: 座標を半径だけ広げた外接矩形を升目の範囲へ直します。
    /// - Parameters:
    ///   - coordinate: 中心の座標。
    ///   - radiusMeters: 半径(m)。負の値と有限でない値は 0 とみなします。
    /// - Returns: 外接矩形と重なる升目の集合。
    func cells(around coordinate: GeoCoordinate, radiusMeters: Double) -> Set<RoadRegulationCellKey> {
        guard let point = GeoBoundingBox(enclosing: [coordinate]) else { return [cell(containing: coordinate)] }
        return Set(cellsOverlapping(point.expanded(byMeters: radiusMeters), limit: nil) ?? [])
    }

    /// 形状を割り当てる升目を昇順・重複なしで返します。
    ///
    /// 責務: 点は各点の升目、線は200 m 以下の小片ごとの外接矩形と重なる升目、面は外接矩形と重なる升目を求め、
    /// どの形でも進入方向の点の升目を加えます。
    /// - Parameters:
    ///   - geometry: 規制の形状。
    ///   - shape: 形状の種類。
    /// - Returns: 升目の配列。升目の数が `maximumCellsPerGeometry` を超えたら `nil`。
    func cells(covering geometry: RoadRegulationGeometry, shape: RoadRegulationShape) -> [RoadRegulationCellKey]? {
        let mainCells: Set<RoadRegulationCellKey>?
        switch shape {
        case .point: mainCells = Set(geometry.mainParts.joined().map(cell(containing:)))
        case .line: mainCells = lineCells(geometry.mainParts)
        case .area: mainCells = areaCells(geometry)
        }
        guard let mainCells else { return nil }
        let allCells = mainCells.union(geometry.approachPoints.map(cell(containing:)))
        guard allCells.count <= Self.maximumCellsPerGeometry else { return nil }
        return allCells.sorted()
    }

    /// 線の各区間を小片に分け、各小片の外接矩形と重なる升目を集めます。
    ///
    /// 責務: 升目の数が上限を超えた時点で打ち切ります。1点だけの区間はその点の升目にします。
    /// - Parameter parts: 線の区間ごとの点の列。
    /// - Returns: 升目の集合。上限を超えたら `nil`。
    private func lineCells(_ parts: [[GeoCoordinate]]) -> Set<RoadRegulationCellKey>? {
        var cells = Set(parts.compactMap { $0.count == 1 ? cell(containing: $0[0]) : nil })
        for part in parts {
            for (start, end) in zip(part, part.dropFirst()) {
                guard addSegmentCells(from: start, to: end, into: &cells) else { return nil }
            }
        }
        return cells
    }

    /// 1つの線分を小片に分け、各小片の外接矩形と重なる升目を加えます。
    ///
    /// 責務: 小片の数を ceil(長さ / 200 m)(最低1)とし、緯度・経度を線形に分けた各小片の升目を加えます。
    /// - Parameters:
    ///   - start: 線分の始点。
    ///   - end: 線分の終点。
    ///   - cells: 升目を加える集合。
    /// - Returns: 升目の数が上限以内なら `true`。超えたら途中で打ち切って `false`。
    private func addSegmentCells(from start: GeoCoordinate, to end: GeoCoordinate, into cells: inout Set<RoadRegulationCellKey>) -> Bool {
        let pieceCount = max(1, Int((distanceCalculator.distanceMeters(start, end) / Self.segmentPieceMeters).rounded(.up)))
        let latitudeSpan = end.latitude - start.latitude
        let longitudeSpan = end.longitude - start.longitude
        for piece in 0..<pieceCount {
            let from = Double(piece) / Double(pieceCount)
            let to = Double(piece + 1) / Double(pieceCount)
            let pieceCells = cellsOverlapping(
                latitudes: (start.latitude + latitudeSpan * from, start.latitude + latitudeSpan * to),
                longitudes: (start.longitude + longitudeSpan * from, start.longitude + longitudeSpan * to),
                limit: Self.maximumCellsPerGeometry
            )
            guard let pieceCells else { return false }
            cells.formUnion(pieceCells)
            guard cells.count <= Self.maximumCellsPerGeometry else { return false }
        }
        return true
    }

    /// 面の外接矩形と重なる升目を返します。
    ///
    /// 責務: 規制場所と進入方向の点の外接矩形を升目の範囲へ直します。
    /// - Parameter geometry: 面の形状。
    /// - Returns: 升目の集合。点が無ければ空。上限を超えたら `nil`。
    private func areaCells(_ geometry: RoadRegulationGeometry) -> Set<RoadRegulationCellKey>? {
        guard let box = geometry.boundingBox else { return [] }
        return cellsOverlapping(box, limit: Self.maximumCellsPerGeometry).map(Set.init)
    }

    /// 外接矩形と重なる升目を返します。
    ///
    /// 責務: 外接矩形の4辺を升目の範囲へ直します。
    /// - Parameters:
    ///   - box: 外接矩形。
    ///   - limit: 升目の数の上限。`nil` なら上限なし。
    /// - Returns: 升目の配列。上限を超えるなら `nil`。
    private func cellsOverlapping(_ box: GeoBoundingBox, limit: Int?) -> [RoadRegulationCellKey]? {
        cellsOverlapping(
            latitudes: (box.minLatitude, box.maxLatitude),
            longitudes: (box.minLongitude, box.maxLongitude),
            limit: limit
        )
    }

    /// 緯度・経度の範囲と重なる升目を返します。
    ///
    /// 責務: 両端の升目番号から行と列の範囲を決め、数が上限以内なら列挙します。
    /// - Parameters:
    ///   - latitudes: 緯度の両端(順不同)。
    ///   - longitudes: 経度の両端(順不同)。
    ///   - limit: 升目の数の上限。`nil` なら上限なし。
    /// - Returns: 升目の配列。上限を超えるなら `nil`。
    private func cellsOverlapping(
        latitudes: (Double, Double),
        longitudes: (Double, Double),
        limit: Int?
    ) -> [RoadRegulationCellKey]? {
        let rows = Self.row(ofLatitude: min(latitudes.0, latitudes.1))...Self.row(ofLatitude: max(latitudes.0, latitudes.1))
        let columns = Self.column(ofLongitude: min(longitudes.0, longitudes.1))...Self.column(ofLongitude: max(longitudes.0, longitudes.1))
        if let limit, rows.count * columns.count > limit { return nil }
        return rows.flatMap { row in columns.map { RoadRegulationCellKey(row: row, column: $0) } }
    }

    /// 緯度から升目の行番号を返します。
    ///
    /// 責務: floor((緯度 + 90) × 240) を求めます。
    /// - Parameter latitude: 緯度(度)。
    /// - Returns: 行番号。
    private static func row(ofLatitude latitude: Double) -> Int {
        index(of: (latitude + 90) * Double(rowsPerDegree))
    }

    /// 経度から升目の列番号を返します。
    ///
    /// 責務: floor((経度 + 180) × 160) を求めます。
    /// - Parameter longitude: 経度(度)。
    /// - Returns: 列番号。
    private static func column(ofLongitude longitude: Double) -> Int {
        index(of: (longitude + 180) * Double(columnsPerDegree))
    }

    /// 升目単位の値を升目番号へ切り下げます。
    ///
    /// 責務: 整数との差が許容差以内の値は境目ちょうどとみなして、その整数(北側・東側の升目)にします。
    /// - Parameter scaled: 升目単位の値(0以上の有限値)。
    /// - Returns: 升目番号。
    private static func index(of scaled: Double) -> Int {
        let nearest = scaled.rounded()
        return Int(abs(scaled - nearest) <= boundarySnapTolerance ? nearest : scaled.rounded(.down))
    }
}
