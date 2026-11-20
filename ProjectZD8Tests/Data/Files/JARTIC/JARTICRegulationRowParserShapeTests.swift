import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICRegulationRowParser` の §3.1 の規則7(点・線・面の形状の検査と、面の自動の閉じ)を検証します。
@MainActor
final class JARTICRegulationRowParserShapeTests: XCTestCase {
    private typealias Builder = TestJARTICRegulationRowBuilder
    private typealias Expect = TestJARTICRegulationRecordExpectation

    private func point(_ longitude: Double, _ latitude: Double) -> GeoCoordinate {
        Builder.coordinate(longitude: longitude, latitude: latitude)
    }

    private func draft(coordinates: String, kind: Int = 112) throws -> RoadRegulationDraft {
        try Expect.draft(try Builder.parse([JARTICColumnName.coordinates: coordinates], kind: kind))
    }

    private func rejection(coordinates: String, kind: Int = 112) throws -> RoadRegulationArchiveRecord {
        try Builder.parse([JARTICColumnName.coordinates: coordinates], kind: kind)
    }

    // MARK: 規則7 形状

    /// 線が1点だけなら `invalidGeometry` です。
    func testLineWithSinglePointIsInvalidGeometry() throws {
        Expect.assertRejected(try rejection(coordinates: "127.5 26.2"), .invalidGeometry)
    }

    /// 線の連続する同じ点は1つにまとめるので、同じ点2つだけなら `invalidGeometry` です。
    func testLineWithOnlyDuplicatePointsIsInvalidGeometry() throws {
        Expect.assertRejected(try rejection(coordinates: "127.5 26.2;127.5 26.2"), .invalidGeometry)
    }

    /// 連続する同じ点をまとめた上で、異なる2点以上の線は採用されます。
    func testLineDuplicatePointsAreMergedWhenAccepted() throws {
        let result = try draft(coordinates: "127.5 26.2;127.5 26.2;127.6 26.3")
        XCTAssertEqual(result.geometry.mainParts, [[point(127.5, 26.2), point(127.6, 26.3)]])
    }

    /// `/` で分けた複数の区間は、それぞれ2点以上なら主の区間が複数になります。
    func testLineWithMultipleSegments() throws {
        let result = try draft(coordinates: "127.5 26.2;127.6 26.3/127.7 26.4;127.8 26.5")
        XCTAssertEqual(result.geometry.mainParts.count, 2)
        XCTAssertEqual(result.geometry.mainParts.last, [point(127.7, 26.4), point(127.8, 26.5)])
    }

    /// 線の区間のうち1つでも異なる2点未満なら `invalidGeometry` です。
    func testLineWithOneShortSegmentIsInvalidGeometry() throws {
        Expect.assertRejected(try rejection(coordinates: "127.5 26.2;127.6 26.3/127.7 26.4"), .invalidGeometry)
    }

    /// 点規制は、区間1つ・点1つなら採用されます。
    func testPointWithSinglePointIsAccepted() throws {
        let result = try draft(coordinates: "127.5 26.2", kind: 63)
        XCTAssertEqual(result.geometry.mainParts, [[point(127.5, 26.2)]])
    }

    /// 点規制に2点ある場合は `invalidGeometry` です。
    func testPointWithTwoPointsIsInvalidGeometry() throws {
        Expect.assertRejected(try rejection(coordinates: "127.5 26.2;127.6 26.3", kind: 63), .invalidGeometry)
    }

    /// 点規制に区間が2つある場合は `invalidGeometry` です。
    func testPointWithTwoSegmentsIsInvalidGeometry() throws {
        Expect.assertRejected(try rejection(coordinates: "127.5 26.2/127.6 26.3", kind: 63), .invalidGeometry)
    }

    /// 面が閉じていなければ、先頭の点を末尾に足します。
    func testAreaIsClosedAutomatically() throws {
        let result = try draft(coordinates: "127.5 26.2;127.6 26.2;127.6 26.3", kind: 114)
        XCTAssertEqual(
            result.geometry.mainParts,
            [[point(127.5, 26.2), point(127.6, 26.2), point(127.6, 26.3), point(127.5, 26.2)]]
        )
    }

    /// 閉じている面は、そのままです(点を足さない)。
    func testClosedAreaIsKeptAsIs() throws {
        let result = try draft(coordinates: "127.5 26.2;127.6 26.2;127.6 26.3;127.5 26.2", kind: 114)
        XCTAssertEqual(result.geometry.mainParts.first?.count, 4)
        XCTAssertEqual(result.geometry.mainParts.first?.last, point(127.5, 26.2))
    }

    /// 異なる点が3つ未満の面(閉じた2点を含む)は `invalidGeometry` です。
    func testAreaWithFewerThanThreeDistinctPointsIsInvalidGeometry() throws {
        Expect.assertRejected(try rejection(coordinates: "127.5 26.2;127.6 26.3", kind: 114), .invalidGeometry)
        Expect.assertRejected(try rejection(coordinates: "127.5 26.2;127.6 26.3;127.5 26.2", kind: 114), .invalidGeometry)
    }
}
