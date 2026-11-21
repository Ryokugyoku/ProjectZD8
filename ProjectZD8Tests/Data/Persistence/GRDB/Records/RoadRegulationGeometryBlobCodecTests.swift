import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationGeometryBlobCodec` の往復・バイト列の形式・壊れた入力の拒否を検証します。
@MainActor
final class RoadRegulationGeometryBlobCodecTests: XCTestCase {
    private typealias Fixtures = GRDBRoadRegulationFixtures
    private let codec = RoadRegulationGeometryBlobCodec()

    /// 版1・リトルエンディアンの形式を、手で組んだバイト列で作ります。
    private func bytes(parts: [(role: UInt8, points: [(lon: Int32, lat: Int32)])], version: UInt8 = 1) -> Data {
        var out: [UInt8] = [version] + le(UInt16(parts.count))
        for part in parts {
            out.append(part.role)
            out += le(UInt32(part.points.count))
            for point in part.points { out += le(UInt32(bitPattern: point.lon)) + le(UInt32(bitPattern: point.lat)) }
        }
        return Data(out)
    }

    /// 整数をリトルエンディアンのバイト列にします。
    private func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        (0..<(T.bitWidth / 8)).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }

    /// 点・線・面と、役割の違う複数の部分が、1e-7 度以内で往復します。
    ///
    /// 責務: 一時停止(点+進入方向)・線・面・除外つきの複数の部分を往復させ、座標の誤差と順序を確認します。
    func testRoundTripOfPointLineAreaAndMultipleParts() throws {
        let multi = RoadRegulationGeometry(parts: [
            RoadRegulationGeometryPart(role: .main, coordinates: [Fixtures.point(26.2231795618476, 127.719496353425), Fixtures.point(26.2241795, 127.7205123)]),
            RoadRegulationGeometryPart(role: .main, coordinates: [Fixtures.point(35.0, 139.0), Fixtures.point(35.1, 139.1), Fixtures.point(35.2, 139.3)]),
            RoadRegulationGeometryPart(role: .approach, coordinates: [Fixtures.point(26.2, 127.7)]),
            RoadRegulationGeometryPart(role: .exclusion, coordinates: [Fixtures.point(26.3, 127.8), Fixtures.point(26.31, 127.81)])
        ])
        let geometries = RoadRegulationKind.allCases.map { Fixtures.geometry(for: $0) } + [multi]

        for geometry in geometries {
            let decoded = try codec.decode(codec.encode(geometry))
            XCTAssertEqual(decoded.parts.map(\.role), geometry.parts.map(\.role))
            XCTAssertEqual(decoded.parts.map(\.coordinates.count), geometry.parts.map(\.coordinates.count))
            for (original, restored) in zip(geometry.parts.flatMap(\.coordinates), decoded.parts.flatMap(\.coordinates)) {
                XCTAssertEqual(restored.latitude, original.latitude, accuracy: 1e-7)
                XCTAssertEqual(restored.longitude, original.longitude, accuracy: 1e-7)
            }
        }
    }

    /// 端の座標(経度 ±180、緯度 ±90、負の値)でも Int32 に収まり往復します。
    ///
    /// 責務: 1.8e9 の経度と、負の最小の刻みを往復させます。
    func testExtremeCoordinatesRoundTrip() throws {
        let coordinates = [
            Fixtures.point(90, 180), Fixtures.point(-90, -180), Fixtures.point(-0.0000001, -0.0000001), Fixtures.point(0, 0),
            Fixtures.point(89.9999999, 179.9999999)
        ]
        let geometry = RoadRegulationGeometry(parts: [RoadRegulationGeometryPart(role: .main, coordinates: coordinates)])

        let decoded = try codec.decode(codec.encode(geometry))

        for (original, restored) in zip(coordinates, decoded.parts[0].coordinates) {
            XCTAssertEqual(restored.latitude, original.latitude, accuracy: 1e-7)
            XCTAssertEqual(restored.longitude, original.longitude, accuracy: 1e-7)
        }
    }

    /// 符号化の形式は、設計書のバイト列と一致します。
    ///
    /// 責務: 版1・区間数・役割・点数・(経度 × 1e7, 緯度 × 1e7) の Int32 リトルエンディアン(負は2の補数)を、手で組んだ期待値と比べます。
    func testEncodedBytesMatchSpecifiedLayout() {
        let geometry = RoadRegulationGeometry(parts: [
            RoadRegulationGeometryPart(role: .main, coordinates: [Fixtures.point(26.5, 127.25), Fixtures.point(-0.0000001, -0.0000002)]),
            RoadRegulationGeometryPart(role: .exclusion, coordinates: [Fixtures.point(1, 2)])
        ])
        let expected = bytes(parts: [
            (role: 0, points: [(lon: 1_272_500_000, lat: 265_000_000), (lon: -2, lat: -1)]),
            (role: 2, points: [(lon: 20_000_000, lat: 10_000_000)])
        ])

        XCTAssertEqual(codec.encode(geometry), expected)
    }

    /// 手で組んだ正しいバイト列を復元できます(エンコーダの出力を写さない確認)。
    ///
    /// 責務: 独立に組んだ入力から、役割・点数・座標を復元することを確認します。
    func testDecodesHandBuiltBytes() throws {
        let data = bytes(parts: [(role: 1, points: [(lon: 1_272_500_000, lat: 265_000_000)])])

        let geometry = try codec.decode(data)

        XCTAssertEqual(geometry.parts.count, 1)
        XCTAssertEqual(geometry.parts[0].role, .approach)
        XCTAssertEqual(geometry.parts[0].coordinates[0].latitude, 26.5, accuracy: 1e-9)
        XCTAssertEqual(geometry.parts[0].coordinates[0].longitude, 127.25, accuracy: 1e-9)
    }

    /// 復元できない入力が `integrityConflict` で拒否されることを確認します。
    private func assertIntegrityConflict(_ data: Data, _ label: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try codec.decode(data), label, file: file, line: line) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .integrityConflict, label, file: file, line: line)
        }
    }

    /// 版違いは投げます。
    ///
    /// 責務: 版 0・2・255 を拒否することを確認します。
    func testUnknownVersionThrows() {
        for version: UInt8 in [0, 2, 255] {
            let data = bytes(parts: [(role: 0, points: [(lon: 1, lat: 1)])], version: version)
            assertIntegrityConflict(data, "version \(version)")
        }
    }

    /// 途中で切れている入力は、どの長さでも投げます。
    ///
    /// 責務: 正しい入力の、全体より短いすべての先頭部分を拒否することを確認します。
    func testEveryTruncatedPrefixThrows() throws {
        let full = bytes(parts: [(role: 0, points: [(lon: 1, lat: 1), (lon: 2, lat: 2)]), (role: 1, points: [(lon: 3, lat: 3)])])
        XCTAssertNoThrow(try codec.decode(full))

        for length in 0..<full.count {
            assertIntegrityConflict(Data(full.prefix(length)), "length \(length)")
        }
    }

    /// 役割が不明な区間と、点数 0 の区間は投げます。
    ///
    /// 責務: 役割 3・255 と点数 0 の入力を拒否することを確認します。
    func testUnknownRoleAndZeroPointsThrow() {
        assertIntegrityConflict(bytes(parts: [(role: 3, points: [(lon: 1, lat: 1)])]), "role 3")
        assertIntegrityConflict(bytes(parts: [(role: 255, points: [(lon: 1, lat: 1)])]), "role 255")
        assertIntegrityConflict(bytes(parts: [(role: 0, points: [])]), "zero points")
    }

    /// 点数が実際の長さより大きいと宣言された入力は投げます。
    ///
    /// 責務: 巨大な点数の宣言で確保や読み過ぎをせずに失敗することを確認します。
    func testDeclaredPointCountLargerThanDataThrows() {
        var raw = [UInt8](bytes(parts: [(role: 0, points: [(lon: 1, lat: 1)])]))
        raw.replaceSubrange(4..<8, with: le(UInt32.max))

        assertIntegrityConflict(Data(raw))
    }

    /// 座標が範囲外の点と、余りのバイトは投げます。
    ///
    /// 責務: 緯度 100 度・経度 200 度に当たる値と、正しい入力の後ろに1バイト足した入力を拒否することを確認します。
    func testOutOfRangeCoordinateAndTrailingBytesThrow() {
        assertIntegrityConflict(bytes(parts: [(role: 0, points: [(lon: 0, lat: 1_000_000_000)])]), "latitude 100")
        assertIntegrityConflict(bytes(parts: [(role: 0, points: [(lon: 2_000_000_000, lat: 0)])]), "longitude 200")
        assertIntegrityConflict(bytes(parts: [(role: 0, points: [(lon: -2_000_000_000, lat: 0)])]), "longitude -200")
        var valid = bytes(parts: [(role: 0, points: [(lon: 1, lat: 1)])])
        XCTAssertNoThrow(try codec.decode(valid))
        valid.append(0)
        assertIntegrityConflict(valid, "trailing byte")
    }

    /// 符号化した最小の形状でも、DB の `length(geometry) >= 3` を満たします。
    ///
    /// 責務: 1点だけの形状のバイト数が 3 以上であることを確認します。
    func testSmallestEncodedGeometryIsAtLeastThreeBytes() {
        let geometry = RoadRegulationGeometry(parts: [RoadRegulationGeometryPart(role: .main, coordinates: [Fixtures.point(1, 1)])])

        XCTAssertGreaterThanOrEqual(codec.encode(geometry).count, 3)
    }
}
