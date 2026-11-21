import XCTest
@testable import ProjectZD8

/// `RoadRegulationGrid`(2分の1地域メッシュと同じ刻みの升目)の形状(点・線・面・一時停止)から升目への割り当てを、設計書 §1.4 の値で検証します。
final class RoadRegulationGridCoveringTests: XCTestCase {
    private let grid = RoadRegulationGrid()
    private let geo = GeoTestCoordinates()

    /// 責務: 緯度・経度から座標を作ります(範囲外ならテストの誤りとして失敗させます)。
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> GeoCoordinate {
        try XCTUnwrap(GeoCoordinate(latitude: latitude, longitude: longitude))
    }

    /// 責務: 升目 (row, column) の中心の座標を返します。緯度 = row/240 − 90 + 1/480、経度 = column/160 − 180 + 1/320。
    private func center(row: Int, column: Int) throws -> GeoCoordinate {
        try coordinate(Double(row) / 240 - 90 + 1.0 / 480, Double(column) / 160 - 180 + 1.0 / 320)
    }

    /// 責務: 形状(規制場所の区間だけ)を作ります。
    private func geometry(_ parts: [[GeoCoordinate]]) -> RoadRegulationGeometry {
        RoadRegulationGeometry(parts: parts.map { RoadRegulationGeometryPart(role: .main, coordinates: $0) })
    }

    // MARK: cells(covering:shape:) 点・線

    /// 責務: 点の形状は、各点の升目だけを昇順・重複なしで返すことを確かめます。
    func testCoveringPointShapeReturnsSortedUniqueCells() throws {
        let high = try center(row: 27_900, column: 49_240)
        let low = try center(row: 27_893, column: 49_235)
        let result = try XCTUnwrap(grid.cells(covering: geometry([[high], [low], [low]]), shape: .point))
        XCTAssertEqual(result, [RoadRegulationCellKey(row: 27_893, column: 49_235), RoadRegulationCellKey(row: 27_900, column: 49_240)])
    }

    /// 責務: 東へ 2 km の線分が、通る升目をすべて含む(25 m ごとの点の升目を含む)ことを確かめます。
    func testCoveringEastwardLineContainsEveryCellItPasses() throws {
        let line = geo.points([(0, 0), (2_000, 0)])
        let result = try XCTUnwrap(grid.cells(covering: geometry([line]), shape: .line))
        for step in 0...80 {
            let sample = geo.point(x: Double(step) * 25, y: 0)
            XCTAssertTrue(result.contains(grid.cell(containing: sample)), "x = \(step * 25) m の升目が欠けています")
        }
        XCTAssertEqual(result, result.sorted())
        XCTAssertEqual(Set(result).count, result.count)
    }

    /// 責務: 斜めの長い線分(北東へ約 3 km)でも、通る升目の取りこぼしが無いことを確かめます。
    func testCoveringDiagonalLineContainsEveryCellItPasses() throws {
        let line = geo.points([(0, 0), (2_100, 2_100)])
        let result = try XCTUnwrap(grid.cells(covering: geometry([line]), shape: .line))
        for step in 0...210 {
            let offset = Double(step) * 10
            XCTAssertTrue(result.contains(grid.cell(containing: geo.point(x: offset, y: offset))), "\(step) 番目の升目が欠けています")
        }
    }

    /// 責務: 折れ線の各線分と、複数の区間のすべてを含むことを確かめます。
    func testCoveringLineIncludesAllSegmentsAndParts() throws {
        let first = geo.points([(0, 0), (500, 0), (500, 500)])
        let second = geo.points([(5_000, 5_000), (5_300, 5_000)])
        let result = try XCTUnwrap(grid.cells(covering: geometry([first, second]), shape: .line))
        for point in [(0.0, 0.0), (500.0, 0.0), (500.0, 500.0), (5_000.0, 5_000.0), (5_300.0, 5_000.0), (250.0, 0.0), (500.0, 250.0)] {
            XCTAssertTrue(result.contains(grid.cell(containing: geo.point(x: point.0, y: point.1))))
        }
    }

    /// 責務: 点が1つだけの線は、その点の升目を返すことを確かめます。
    func testCoveringLineWithSinglePointContainsItsCell() throws {
        let point = try center(row: 27_893, column: 49_235)
        let result = try XCTUnwrap(grid.cells(covering: geometry([[point]]), shape: .line))
        XCTAssertEqual(result, [grid.cell(containing: point)])
    }

    // MARK: cells(covering:shape:) 面・一時停止

    /// 責務: 3×3升にまたがる面が、外接矩形の9升をすべて含むことを確かめます。
    func testCoveringAreaReturnsAllCellsOfBoundingBox() throws {
        let ring = [
            try center(row: 27_893, column: 49_235), try center(row: 27_893, column: 49_237),
            try center(row: 27_895, column: 49_237), try center(row: 27_895, column: 49_235)
        ]
        let result = try XCTUnwrap(grid.cells(covering: geometry([ring]), shape: .area))
        let expected = (27_893...27_895).flatMap { row in (49_235...49_237).map { RoadRegulationCellKey(row: row, column: $0) } }
        XCTAssertEqual(result, expected)
    }

    /// 責務: 外接矩形がちょうど 10,000 升(100×100)なら返り、101×100 升なら `nil` になることを確かめます。
    func testCoveringAreaAtMaximumCellCountBoundary() throws {
        func ring(columns: Int) throws -> [GeoCoordinate] {
            [
                try center(row: 20_000, column: 40_000), try center(row: 20_000, column: 40_000 + columns - 1),
                try center(row: 20_099, column: 40_000 + columns - 1), try center(row: 20_099, column: 40_000)
            ]
        }
        let atLimit = grid.cells(covering: geometry([try ring(columns: 100)]), shape: .area)
        XCTAssertEqual(atLimit?.count, 10_000)
        XCTAssertNil(grid.cells(covering: geometry([try ring(columns: 101)]), shape: .area))
    }

    /// 責務: 外接矩形が 10,000 升を大きく超える面(約 1 度四方 = 38,400 升)が `nil` になることを確かめます。
    func testCoveringHugeAreaReturnsNil() throws {
        let ring = [try coordinate(26, 127), try coordinate(26, 128), try coordinate(27, 128), try coordinate(27, 127)]
        XCTAssertNil(grid.cells(covering: geometry([ring]), shape: .area))
    }

    /// 責務: 一時停止の形状が、停止点と進入方向の点の両方の升目を含むことを確かめます。
    func testCoveringStopIncludesStopPointAndApproachPoint() throws {
        let stop = try center(row: 27_893, column: 49_235)
        let approach = try center(row: 27_893, column: 49_238)
        let stopGeometry = RoadRegulationGeometry(parts: [
            RoadRegulationGeometryPart(role: .main, coordinates: [stop]),
            RoadRegulationGeometryPart(role: .approach, coordinates: [approach])
        ])
        let result = try XCTUnwrap(grid.cells(covering: stopGeometry, shape: .point))
        XCTAssertEqual(result, [grid.cell(containing: stop), grid.cell(containing: approach)])
    }
}
