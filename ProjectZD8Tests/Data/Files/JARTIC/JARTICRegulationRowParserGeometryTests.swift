import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICRegulationRowParser` の §3.1 の規則6〜9(座標・形状の検査・進入方向・除外の座標)を検証します。
@MainActor
final class JARTICRegulationRowParserGeometryTests: XCTestCase {
    private typealias Builder = TestJARTICRegulationRowBuilder
    private typealias Expect = TestJARTICRegulationRecordExpectation

    private func point(_ longitude: Double, _ latitude: Double) -> GeoCoordinate {
        Builder.coordinate(longitude: longitude, latitude: latitude)
    }

    private func draft(coordinates: String, kind: Int = 112, extra: [String: String] = [:]) throws -> RoadRegulationDraft {
        var overrides = extra
        overrides[JARTICColumnName.coordinates] = coordinates
        return try Expect.draft(try Builder.parse(overrides, kind: kind))
    }

    private func rejection(coordinates: String, kind: Int = 112, extra: [String: String] = [:]) throws -> RoadRegulationArchiveRecord {
        var overrides = extra
        overrides[JARTICColumnName.coordinates] = coordinates
        return try Builder.parse(overrides, kind: kind)
    }

    // MARK: 規則6 座標

    /// 線の座標は「経度 緯度」の順で読み、主の区間になります。
    func testLineCoordinatesAreReadLongitudeFirst() throws {
        let result = try draft(coordinates: "127.5 26.2;127.6 26.3")
        XCTAssertEqual(result.geometry.mainParts, [[point(127.5, 26.2), point(127.6, 26.3)]])
        XCTAssertEqual(result.geometry.mainParts.first?.first?.latitude ?? 0, 26.2, accuracy: 1e-9)
        XCTAssertTrue(result.geometry.approachPoints.isEmpty)
        XCTAssertTrue(result.geometry.exclusionParts.isEmpty)
    }

    /// 緯度と経度を取り違えた座標は `invalidCoordinates` です。
    func testSwappedLatitudeLongitudeIsRejected() throws {
        Expect.assertRejected(try rejection(coordinates: "26.2 127.5;26.3 127.6"), .invalidCoordinates)
    }

    /// 空白2つ・前後の空白があっても読めます。
    func testExtraWhitespaceIsAccepted() throws {
        let result = try draft(coordinates: "  127.5  26.2;127.6   26.3 ")
        XCTAssertEqual(result.geometry.mainParts, [[point(127.5, 26.2), point(127.6, 26.3)]])
    }

    /// 緯度の端(20.0 と 46.0)は有効で、19.99 は `invalidCoordinates` です。
    func testLatitudeBoundaryValues() throws {
        XCTAssertNotNil(try? draft(coordinates: "127.5 20.0;127.5 46.0"))
        Expect.assertRejected(try rejection(coordinates: "127.5 19.99;127.5 26.0"), .invalidCoordinates)
        Expect.assertRejected(try rejection(coordinates: "127.5 26.0;127.5 46.01"), .invalidCoordinates)
    }

    /// 経度の端(122.0 と 154.0)は有効で、その外は `invalidCoordinates` です。
    func testLongitudeBoundaryValues() throws {
        XCTAssertNotNil(try? draft(coordinates: "122.0 26.2;154.0 26.2"))
        Expect.assertRejected(try rejection(coordinates: "121.99 26.2;127.5 26.2"), .invalidCoordinates)
        Expect.assertRejected(try rejection(coordinates: "127.5 26.2;154.01 26.2"), .invalidCoordinates)
    }

    /// 数値でない座標は `invalidCoordinates` です。
    func testNonNumericCoordinatesAreRejected() throws {
        Expect.assertRejected(try rejection(coordinates: "127.5 26.2;abc def"), .invalidCoordinates)
    }

    /// 座標が空(空白だけを含む)なら `missingRequiredField` です。
    func testEmptyCoordinatesAreMissingRequiredField() throws {
        for value in ["", "   "] {
            Expect.assertRejected(try rejection(coordinates: value), .missingRequiredField)
        }
    }

    /// 座標の不正は、形状の検査より先です(1点だけで、かつ不正な値なら `invalidCoordinates`)。
    func testInvalidCoordinatesTakePriorityOverInvalidGeometry() throws {
        Expect.assertRejected(try rejection(coordinates: "abc def"), .invalidCoordinates)
    }
}
