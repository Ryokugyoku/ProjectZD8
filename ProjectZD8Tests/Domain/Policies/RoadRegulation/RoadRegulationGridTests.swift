import XCTest
@testable import ProjectZD8

/// `RoadRegulationGrid`(2分の1地域メッシュと同じ刻みの升目)の鍵・周辺検索・形状の割り当てを、設計書 §1.4 の値で検証します。
final class RoadRegulationGridTests: XCTestCase {
    private let grid = RoadRegulationGrid()
    private let metersPerDegree = GeoTestCoordinates.metersPerDegree

    /// 責務: 緯度・経度から座標を作ります(範囲外ならテストの誤りとして失敗させます)。
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> GeoCoordinate {
        try XCTUnwrap(GeoCoordinate(latitude: latitude, longitude: longitude))
    }

    /// 責務: 升目 (row, column) の中心の座標を返します。緯度 = row/240 − 90 + 1/480、経度 = column/160 − 180 + 1/320。
    private func center(row: Int, column: Int) throws -> GeoCoordinate {
        try coordinate(Double(row) / 240 - 90 + 1.0 / 480, Double(column) / 160 - 180 + 1.0 / 320)
    }

    // MARK: 定数・cell(containing:)

    /// 責務: 升目の刻みと上限の定数が設計書どおりであることを確かめます。
    func testConstantsMatchDesign() {
        XCTAssertEqual(RoadRegulationGrid.rowsPerDegree, 240)
        XCTAssertEqual(RoadRegulationGrid.columnsPerDegree, 160)
        XCTAssertEqual(RoadRegulationGrid.maximumCellsPerGeometry, 10_000)
        XCTAssertEqual(RoadRegulationGrid.segmentPieceMeters, 200.0)
    }

    /// 責務: 設計書の例 (26.2231795618476, 127.719496353425) が row 27893・col 49235・key 1,828,044,883 になることを確かめます。
    /// 計算: floor((26.2231795618476+90)×240) = 27893、floor((127.719496353425+180)×160) = 49235、27893×65,536 + 49235 = 1,828,044,883。
    func testCellContainingDesignExample() throws {
        let key = grid.cell(containing: try coordinate(26.2231795618476, 127.719496353425))
        XCTAssertEqual(key.row, 27893)
        XCTAssertEqual(key.column, 49235)
        XCTAssertEqual(key.rawValue, 1_828_044_883)
    }

    /// 責務: 緯度がちょうど 1/240 の倍数の点が北側の升目になることを確かめます。
    /// 緯度 0.25 度は (0.25+90)×240 = 21,660(厳密)なので row 21,660。わずかに南なら 21,659。
    func testLatitudeOnCellBoundaryBelongsToNorthernCell() throws {
        XCTAssertEqual(grid.cell(containing: try coordinate(0.25, 10)).row, 21_660)
        XCTAssertEqual(grid.cell(containing: try coordinate(0, 10)).row, 21_600)
        XCTAssertEqual(grid.cell(containing: try coordinate(0.25 - 1e-6, 10)).row, 21_659)
    }

    /// 責務: 経度がちょうど 1/160 の倍数の点が東側の升目になることを確かめます。
    /// 経度 0 度は (0+180)×160 = 28,800(厳密)、0.5 度は 28,880。わずかに西なら 1 小さい。
    func testLongitudeOnCellBoundaryBelongsToEasternCell() throws {
        XCTAssertEqual(grid.cell(containing: try coordinate(10, 0)).column, 28_800)
        XCTAssertEqual(grid.cell(containing: try coordinate(10, 0.5)).column, 28_880)
        XCTAssertEqual(grid.cell(containing: try coordinate(10, 0.5 - 1e-6)).column, 28_879)
    }

    /// 責務: 座標範囲の端(南西端・経度180度・北極)でも鍵が作れることを確かめます。
    /// 南西端は row 0・col 0、経度 180 度は col 57,600、緯度 90 度は row 43,200。
    func testCellContainingAtExtremes() throws {
        let southWest = grid.cell(containing: try coordinate(-90, -180))
        XCTAssertEqual(southWest.row, 0)
        XCTAssertEqual(southWest.column, 0)
        XCTAssertEqual(grid.cell(containing: try coordinate(0, 180)).column, 57_600)
        XCTAssertEqual(grid.cell(containing: try coordinate(90, 0)).row, 43_200)
    }

    // MARK: cells(around:radiusMeters:)

    /// 責務: 升目の中心から半径 120 m は、その1升だけであることを確かめます。
    func testCellsAroundCellCenterReturnsSingleCell() throws {
        let point = try center(row: 27_893, column: 49_235)
        XCTAssertEqual(grid.cells(around: point, radiusMeters: 120), [RoadRegulationCellKey(row: 27_893, column: 49_235)])
    }

    /// 責務: 升目の角(南西端)から内側へ 10 m の点は、半径 120 m で隣接を含む4升になることを確かめます。
    func testCellsAroundPointNearCornerReturnsFourCells() throws {
        let cornerLatitude = 27_893.0 / 240 - 90
        let cornerLongitude = 49_235.0 / 160 - 180
        let metersPerLongitudeDegree = metersPerDegree * cos(cornerLatitude * Double.pi / 180)
        let point = try coordinate(cornerLatitude + 10 / metersPerDegree, cornerLongitude + 10 / metersPerLongitudeDegree)
        let expected: Set = [
            RoadRegulationCellKey(row: 27_893, column: 49_235), RoadRegulationCellKey(row: 27_892, column: 49_235),
            RoadRegulationCellKey(row: 27_893, column: 49_234), RoadRegulationCellKey(row: 27_892, column: 49_234)
        ]
        XCTAssertEqual(grid.cells(around: point, radiusMeters: 120), expected)
    }

    /// 責務: 半径が 0 や負の時は、その点の升目だけを返す(落ちない)ことを確かめます。
    func testCellsAroundWithZeroOrNegativeRadiusReturnsOwnCell() throws {
        let point = try center(row: 27_893, column: 49_235)
        let own: Set = [grid.cell(containing: point)]
        XCTAssertEqual(grid.cells(around: point, radiusMeters: 0), own)
        XCTAssertEqual(grid.cells(around: point, radiusMeters: -50), own)
    }

    /// 中心は升の中央なので、北へ 2 km は +4.32 升で row 27,897 まで、西へ 2 km は −3.21 升で col 49,232 まで届き、49,231 には届かない。
    /// 責務: 半径が大きいと升目が増え、自分の升目を必ず含むことを確かめます(半径2 km: 緯度方向は 463 m/升、経度方向は約 623 m/升)。
    func testCellsAroundWithLargeRadiusContainsNeighbours() throws {
        let point = try center(row: 27_893, column: 49_235)
        let cells = grid.cells(around: point, radiusMeters: 2_000)
        XCTAssertTrue(cells.contains(grid.cell(containing: point)))
        XCTAssertTrue(cells.contains(RoadRegulationCellKey(row: 27_896, column: 49_235)))
        XCTAssertTrue(cells.contains(RoadRegulationCellKey(row: 27_893, column: 49_232)))
        XCTAssertGreaterThan(cells.count, 9)
    }

    /// 責務: 経度 180 度の端付近で、列が範囲(最大 57,600)を超えないことを確かめます。
    func testCellsAroundNearAntimeridianStaysInRange() throws {
        let point = try coordinate(0, 179.9999)
        let cells = grid.cells(around: point, radiusMeters: 1_000)
        XCTAssertTrue(cells.contains(grid.cell(containing: point)))
        XCTAssertTrue(cells.allSatisfy { $0.column <= 57_600 })
    }
}
