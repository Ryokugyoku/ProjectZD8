import Foundation

/// JARTIC の CSV の1行から、規制の形状(本体・進入方向・除外)を読む型です。
///
/// 設計書 §3.1 の 6〜9 を担います。
/// - 6: 規制場所の経度緯度を読む。不正なら `invalidCoordinates`、空なら `missingRequiredField`。
/// - 7: 形状の検査(違反は `invalidGeometry`)。点は区間1つで点1つ、線は各区間に異なる2点以上、
///   面は各区間に異なる3点以上で、閉じていなければ先頭の点を末尾に足す。
/// - 8: 一時停止だけ、進入方向(座標)の全点を1点ずつ `approach` の区間にする。0点なら `missingApproachCoordinates`。
/// - 9: 除外区間及び区域の経度緯度があれば `exclusion` の区間にする。
nonisolated struct JARTICRegulationGeometryReader: Sendable {
    /// 規制場所の経度緯度の列番号。
    private let coordinatesColumn: Int
    /// 進入方向(座標)の列番号。
    private let approachColumn: Int
    /// 除外区間及び区域の経度緯度の列番号。
    private let exclusionColumn: Int
    /// 座標の項目を読む型。
    private let coordinateParser = JARTICCoordinateListParser()

    /// 列番号の表から作ります。
    ///
    /// 責務: 形状に使う3つの列番号を覚えます。
    /// - Parameter columns: 見出しから引いた列番号。
    init(columns: JARTICRegulationColumns) {
        coordinatesColumn = columns.coordinates
        approachColumn = columns.approachCoordinates
        exclusionColumn = columns.exclusionCoordinates
    }

    /// 1行の形状を読みます。
    ///
    /// 責務: 本体・進入方向(一時停止のみ)・除外の順に読み、1つの形状にまとめます。
    /// - Parameters:
    ///   - row: データの1行。
    ///   - kind: 規制の種別。
    /// - Returns: 形状。
    /// - Throws: 座標や形状が不正なら、理由つきの `JARTICRegulationRowStop`。
    func geometry(of row: JARTICCSVRow, kind: RoadRegulationKind) throws(JARTICRegulationRowStop) -> RoadRegulationGeometry {
        let main = try mainParts(of: row, shape: kind.expectedShape)
        let approach = kind == .stop ? try approachParts(of: row) : []
        let exclusion = try exclusionParts(of: row)
        return RoadRegulationGeometry(parts: main + approach + exclusion)
    }

    /// 規制場所の経度緯度を読み、形状を検査します(§3.1 の 6・7)。
    ///
    /// 責務: 本体の区間を読み、空・不正を理由つきで止め、形状の検査を通した区間を返します。
    /// - Parameters:
    ///   - row: データの1行。
    ///   - shape: 種別が期待する形状。
    /// - Returns: `main` の区間。
    /// - Throws: `invalidCoordinates`・`missingRequiredField`・`invalidGeometry`。
    private func mainParts(of row: JARTICCSVRow, shape: RoadRegulationShape) throws(JARTICRegulationRowStop) -> [RoadRegulationGeometryPart] {
        let parts = try coordinates(in: row, at: coordinatesColumn)
        guard !parts.isEmpty else { throw .rejected(.missingRequiredField) }
        let checked = try Self.checked(parts, shape: shape)
        return checked.map { RoadRegulationGeometryPart(role: .main, coordinates: $0) }
    }

    /// 進入方向(座標)を読みます(§3.1 の 8)。
    ///
    /// 責務: 全区間の全点を、1点ずつ `approach` の区間にします。
    /// - Parameter row: データの1行。
    /// - Returns: `approach` の区間(点1つずつ)。
    /// - Throws: 不正なら `invalidCoordinates`、0点なら `missingApproachCoordinates`。
    private func approachParts(of row: JARTICCSVRow) throws(JARTICRegulationRowStop) -> [RoadRegulationGeometryPart] {
        let points = try coordinates(in: row, at: approachColumn).flatMap { $0 }
        guard !points.isEmpty else { throw .rejected(.missingApproachCoordinates) }
        return points.map { RoadRegulationGeometryPart(role: .approach, coordinates: [$0]) }
    }

    /// 除外区間及び区域の経度緯度を読みます(§3.1 の 9)。
    ///
    /// 責務: あれば各区間を `exclusion` の区間にします。
    /// - Parameter row: データの1行。
    /// - Returns: `exclusion` の区間。項目が空なら `[]`。
    /// - Throws: 不正なら `invalidCoordinates`。
    private func exclusionParts(of row: JARTICCSVRow) throws(JARTICRegulationRowStop) -> [RoadRegulationGeometryPart] {
        try coordinates(in: row, at: exclusionColumn).map { RoadRegulationGeometryPart(role: .exclusion, coordinates: $0) }
    }

    /// 座標の項目を読みます。
    ///
    /// 責務: 座標の読み取りの失敗を `invalidCoordinates` に直します。
    /// - Parameters:
    ///   - row: データの1行。
    ///   - index: 列番号。
    /// - Returns: 区間ごとの点列。空の項目は `[]`。
    /// - Throws: 不正なら `invalidCoordinates`。
    private func coordinates(in row: JARTICCSVRow, at index: Int) throws(JARTICRegulationRowStop) -> [[GeoCoordinate]] {
        guard let parts = coordinateParser.parse(row.field(index)) else { throw .rejected(.invalidCoordinates) }
        return parts
    }

    /// 区間の点列を形状ごとに検査します(§3.1 の 7)。
    ///
    /// 責務: 点・線・面の点の数を確かめ、面は閉じた点列にして返します。
    /// - Parameters:
    ///   - parts: 区間ごとの点列(1つ以上)。
    ///   - shape: 種別が期待する形状。
    /// - Returns: 検査を通した区間(面は閉じたもの)。
    /// - Throws: 点の数が足りない・多すぎるなら `invalidGeometry`。
    private static func checked(_ parts: [[GeoCoordinate]], shape: RoadRegulationShape) throws(JARTICRegulationRowStop) -> [[GeoCoordinate]] {
        switch shape {
        case .point:
            guard parts.count == 1, parts[0].count == 1 else { throw .rejected(.invalidGeometry) }
            return parts
        case .line:
            guard parts.allSatisfy({ distinctCount(of: $0) >= minimumLinePoints }) else { throw .rejected(.invalidGeometry) }
            return parts
        case .area:
            guard parts.allSatisfy({ distinctCount(of: $0) >= minimumAreaPoints }) else { throw .rejected(.invalidGeometry) }
            return parts.map(closed)
        }
    }

    /// 点列の中の異なる点の数を数えます。
    ///
    /// 責務: 同じ点の重複を除いた数を返します。
    /// - Parameter points: 点列。
    /// - Returns: 異なる点の数。
    private static func distinctCount(of points: [GeoCoordinate]) -> Int {
        Set(points).count
    }

    /// 面の点列を閉じます。
    ///
    /// 責務: 先頭と末尾が違えば、先頭の点を末尾に足します。
    /// - Parameter points: 面の点列(1点以上)。
    /// - Returns: 先頭と末尾が同じ点列。
    private static func closed(_ points: [GeoCoordinate]) -> [GeoCoordinate] {
        guard let first = points.first, points.last != first else { return points }
        return points + [first]
    }

    /// 線の各区間に要る、異なる点の最小数。
    private static let minimumLinePoints = 2
    /// 面の各区間に要る、異なる点の最小数。
    private static let minimumAreaPoints = 3
}
