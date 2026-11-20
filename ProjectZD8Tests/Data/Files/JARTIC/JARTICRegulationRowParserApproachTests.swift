import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICRegulationRowParser` の §3.1 の規則8・9(一時停止の進入方向と、除外区間の座標)を検証します。
@MainActor
final class JARTICRegulationRowParserApproachTests: XCTestCase {
    private typealias Builder = TestJARTICRegulationRowBuilder
    private typealias Expect = TestJARTICRegulationRecordExpectation

    private func point(_ longitude: Double, _ latitude: Double) -> GeoCoordinate {
        Builder.coordinate(longitude: longitude, latitude: latitude)
    }

    // MARK: 規則8 進入方向

    /// 一時停止の進入方向が1点なら、進入方向の区間が1つになります。
    func testStopApproachWithOnePoint() throws {
        let result = try Expect.draft(try Builder.parse([JARTICColumnName.approachCoordinates: "127.5 26.3"], kind: 63))
        XCTAssertEqual(result.geometry.parts.filter { $0.role == .approach }.count, 1)
        XCTAssertEqual(result.geometry.approachPoints, [point(127.5, 26.3)])
    }

    /// 進入方向が2点なら、1点ずつの区間が2つ(順序を保つ)になります。
    func testStopApproachWithTwoPointsBecomesTwoParts() throws {
        let result = try Expect.draft(try Builder.parse([JARTICColumnName.approachCoordinates: "127.5 26.3;127.5 26.4"], kind: 63))
        let approach = result.geometry.parts.filter { $0.role == .approach }
        XCTAssertEqual(approach.map(\.coordinates), [[point(127.5, 26.3)], [point(127.5, 26.4)]])
        XCTAssertEqual(result.geometry.mainParts, [[point(127.5, 26.2)]])
    }

    /// 進入方向が3点なら区間が3つです。
    func testStopApproachWithThreePointsBecomesThreeParts() throws {
        let result = try Expect.draft(try Builder.parse([JARTICColumnName.approachCoordinates: "127.5 26.3;127.5 26.4;127.6 26.4"], kind: 63))
        XCTAssertEqual(result.geometry.parts.filter { $0.role == .approach }.count, 3)
    }

    /// 進入方向が空(空白だけを含む)なら `missingApproachCoordinates` です。
    func testStopWithoutApproachIsRejected() throws {
        for value in ["", "  "] {
            let record = try Builder.parse([JARTICColumnName.approachCoordinates: value], kind: 63)
            Expect.assertRejected(record, .missingApproachCoordinates)
        }
    }

    /// 進入方向の座標が不正なら `invalidCoordinates` です。
    func testStopWithInvalidApproachIsRejected() throws {
        let record = try Builder.parse([JARTICColumnName.approachCoordinates: "abc def"], kind: 63)
        Expect.assertRejected(record, .invalidCoordinates)
    }

    /// 一時停止でも、形状の不正(規則7)は進入方向の欠落(規則8)より先です。
    func testStopInvalidGeometryTakesPriorityOverMissingApproach() throws {
        let record = try Builder.parse(
            [JARTICColumnName.coordinates: "127.5 26.2;127.6 26.3", JARTICColumnName.approachCoordinates: ""], kind: 63
        )
        Expect.assertRejected(record, .invalidGeometry)
    }

    // MARK: 規則9 除外

    /// 除外区間の座標があれば、除外の区間になります(`/` で複数)。
    func testExclusionCoordinatesBecomeExclusionParts() throws {
        let result = try Expect.draft(try Builder.parse(
            [JARTICColumnName.exclusionCoordinates: "127.51 26.21;127.52 26.22/127.53 26.23;127.54 26.24"]
        ))
        XCTAssertEqual(
            result.geometry.exclusionParts,
            [[point(127.51, 26.21), point(127.52, 26.22)], [point(127.53, 26.23), point(127.54, 26.24)]]
        )
        XCTAssertEqual(result.geometry.mainParts, [[point(127.5, 26.2), point(127.6, 26.3)]])
    }

    /// 除外の座標が空なら、除外の区間はありません。
    func testEmptyExclusionHasNoExclusionParts() throws {
        let result = try Expect.draft(try Builder.parse([JARTICColumnName.exclusionCoordinates: ""]))
        XCTAssertTrue(result.geometry.exclusionParts.isEmpty)
    }

    /// 除外の座標が不正なら `invalidCoordinates` です。
    func testInvalidExclusionCoordinatesAreRejected() throws {
        let record = try Builder.parse([JARTICColumnName.exclusionCoordinates: "abc def;127.5 26.2"])
        Expect.assertRejected(record, .invalidCoordinates)
    }

    /// 除外の座標の不正は、速度の検査より先です。
    func testInvalidExclusionTakesPriorityOverInvalidSpeed() throws {
        let record = try Builder.parse([JARTICColumnName.exclusionCoordinates: "abc def", JARTICColumnName.speed: "0"])
        Expect.assertRejected(record, .invalidCoordinates)
    }
}
