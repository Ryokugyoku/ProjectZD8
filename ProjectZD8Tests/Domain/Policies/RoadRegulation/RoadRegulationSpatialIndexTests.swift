import XCTest
@testable import ProjectZD8

/// `RoadRegulationSpatialIndex` が、位置の周辺の規制を漏らさず、重複なく id 昇順で返すことを検証します(設計書 §1.4・TB2)。
///
/// 原点(北緯26.2度・東経127.7度)は升目の角です(row = (26.2+90)×240 = 27,888、column = (127.7+180)×160 = 49,232 が整数)。
/// 升目は南北 111,195.08 / 240 ≈ 463 m、東西 111,195.08 × cos 26.2° / 160 ≈ 624 m です。
@MainActor
final class RoadRegulationSpatialIndexTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory

    /// 責務: 東へ x m・北へ y m を中心に、半径 `radius` m の候補の id を返します。
    private func candidateIDs(_ index: RoadRegulationSpatialIndex, x: Double, y: Double, radius: Double = 120) -> [Int64] {
        index.candidates(around: Shapes.coordinate((x: x, y: y)), radiusMeters: radius).map(\.id.rawValue)
    }

    /// 責務: 規制が1件も無い索引は、どこを調べても空を返すことを確かめます。
    func testEmptyIndexReturnsNothing() {
        let index = RoadRegulationSpatialIndex(regulations: [])
        XCTAssertEqual(candidateIDs(index, x: 0, y: 0), [])
    }

    /// 責務: 近くの線・停止点・区域を返し、約3 km 離れた線を返さないことを確かめます。
    func testReturnsNearbyRegulationsAndOmitsFarOnes() {
        let index = RoadRegulationSpatialIndex(regulations: [
            Shapes.line(id: 4, points: [(x: 3_000, y: 0), (x: 3_000, y: 100)]),
            Shapes.stop(id: 2, at: (x: 60, y: 0), approaches: [(x: 60, y: -15)]),
            Shapes.line(id: 1, points: [(x: 30, y: -50), (x: 30, y: 50)]),
            Shapes.zone(id: 3, ring: [(x: -300, y: -300), (x: 300, y: -300), (x: 300, y: 300), (x: -300, y: 300)]),
        ])
        XCTAssertEqual(candidateIDs(index, x: 10, y: 10), [1, 2, 3])
    }

    /// 責務: 結果が入力の順でなく id の昇順になることを確かめます。
    func testResultsAreSortedByID() {
        let index = RoadRegulationSpatialIndex(regulations: [
            Shapes.line(id: 30, points: [(x: -20, y: -50), (x: -20, y: 50)]),
            Shapes.line(id: 10, points: [(x: 20, y: -50), (x: 20, y: 50)]),
            Shapes.line(id: 20, points: [(x: 0, y: -50), (x: 0, y: 50)]),
        ])
        XCTAssertEqual(candidateIDs(index, x: 0, y: 0), [10, 20, 30])
    }

    /// 責務: 東西 4 km の1本の線分(約7列の升目にまたがる)を、点の近くに頂点が無くても漏らさず、1回だけ返すことを確かめます。
    func testLongSegmentSpanningManyCellsIsReturnedOnce() {
        let index = RoadRegulationSpatialIndex(regulations: [
            Shapes.line(id: 7, points: [(x: -2_000, y: 50), (x: 2_000, y: 50)]),
        ])
        XCTAssertEqual(candidateIDs(index, x: 10, y: 10), [7])
        XCTAssertEqual(candidateIDs(index, x: 1_500, y: 0), [7])
    }

    /// 責務: 半径 120 m の範囲が複数の升目にまたがる時、いくつもの升目に割り当てた線・区域を重複させずに返すことを確かめます。
    func testRegulationsInSeveralQueriedCellsAreNotDuplicated() {
        let index = RoadRegulationSpatialIndex(regulations: [
            Shapes.line(id: 1, points: [(x: -500, y: -500), (x: 500, y: 500)]),
            Shapes.zone(id: 2, ring: [(x: -800, y: -800), (x: 800, y: -800), (x: 800, y: 800), (x: -800, y: 800)]),
        ])
        XCTAssertEqual(candidateIDs(index, x: 5, y: 5), [1, 2])
    }

    /// 責務: 升目の境目(原点の経線・緯線)の向こう側 110 m にある規制も、半径 120 m なら返すことを確かめます。
    func testRegulationAcrossCellBoundaryWithinRadiusIsReturned() {
        let index = RoadRegulationSpatialIndex(regulations: [
            Shapes.stop(id: 1, at: (x: -100, y: 10), approaches: [(x: -100, y: -5)]),
            Shapes.stop(id: 2, at: (x: 10, y: -100), approaches: [(x: 10, y: -115)]),
        ])
        XCTAssertEqual(candidateIDs(index, x: 10, y: 10), [1, 2])
    }

    /// 責務: 半径の引数を使うことを確かめます(北へ 1.5 km の規制は、半径 120 m では返さず、半径 2 km では返す)。
    func testRadiusArgumentControlsReach() {
        let index = RoadRegulationSpatialIndex(regulations: [
            Shapes.line(id: 9, points: [(x: 0, y: 1_500), (x: 50, y: 1_500)]),
        ])
        XCTAssertEqual(candidateIDs(index, x: 0, y: 0, radius: 120), [])
        XCTAssertEqual(candidateIDs(index, x: 0, y: 0, radius: 2_000), [9])
    }

    /// 責務: 升目へ割り当てられないほど大きい形状(約 100 km 四方の区域。升目 10,000 個を超える)は、
    /// 遠く離れた位置でも候補に含める(取りこぼさない)ことを確かめます。
    func testOversizedGeometryIsAlwaysCandidate() {
        let index = RoadRegulationSpatialIndex(regulations: [
            Shapes.zone(id: 8, ring: [(x: -50_000, y: -50_000), (x: 50_000, y: -50_000), (x: 50_000, y: 50_000), (x: -50_000, y: 50_000)]),
            Shapes.line(id: 3, points: [(x: 0, y: 0), (x: 0, y: 50)]),
        ])
        XCTAssertEqual(candidateIDs(index, x: 0, y: 10), [3, 8])
        XCTAssertEqual(candidateIDs(index, x: 150_000, y: 150_000), [8])
    }

    /// 責務: 返す規制が登録した値そのもの(形状と種別を含む)であることを確かめます。
    func testReturnsRegisteredRegulationValues() {
        let stop = Shapes.stop(id: 5, at: (x: 0, y: 0), approaches: [(x: 0, y: -15), (x: 15, y: 0)])
        let index = RoadRegulationSpatialIndex(regulations: [stop])
        XCTAssertEqual(index.candidates(around: Shapes.coordinate((x: 0, y: 0)), radiusMeters: 120), [stop])
    }
}
