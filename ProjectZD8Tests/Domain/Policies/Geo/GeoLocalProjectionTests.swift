import XCTest
@testable import ProjectZD8

/// `GeoLocalProjection` の投影・逆投影を、設計書 §2.2 の式と独立に計算した値で検証します。
final class GeoLocalProjectionTests: XCTestCase {
    /// 責務: 緯度・経度から座標を作ります(範囲外ならテストの誤りとして失敗させます)。
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> GeoCoordinate {
        try XCTUnwrap(GeoCoordinate(latitude: latitude, longitude: longitude))
    }

    /// 責務: 原点自身が (0, 0) に投影され、`origin` が保持されることを確かめます。
    func testOriginProjectsToZero() throws {
        let origin = try coordinate(35, 139)
        let projection = GeoLocalProjection(origin: origin)
        XCTAssertEqual(projection.origin, origin)
        XCTAssertEqual(projection.project(origin).x, 0, accuracy: 1e-9)
        XCTAssertEqual(projection.project(origin).y, 0, accuracy: 1e-9)
    }

    /// 責務: 北へ緯度 +0.001 度が y = 111.19508 m、x = 0 になることを確かめます(0.001 × 111,195.0802)。
    func testNorthOffsetProjectsToPositiveY() throws {
        let projection = GeoLocalProjection(origin: try coordinate(35, 139))
        let point = projection.project(try coordinate(35.001, 139))
        XCTAssertEqual(point.x, 0, accuracy: 1e-6)
        XCTAssertEqual(point.y, 111.195_08, accuracy: 0.01)
    }

    /// 責務: 東へ経度 +0.001 度が x = 0.001 × cos(35°) × 111,195.0802 = 91.0857 m になることを確かめます。
    func testEastOffsetProjectsToPositiveX() throws {
        let projection = GeoLocalProjection(origin: try coordinate(35, 139))
        let point = projection.project(try coordinate(35, 139.001))
        XCTAssertEqual(point.x, 91.0857, accuracy: 0.01)
        XCTAssertEqual(point.y, 0, accuracy: 1e-6)
    }

    /// 責務: 南西側(南半球の原点を含む)が負の値になり、cos は原点の緯度で計算されることを確かめます。
    /// 原点 (-33.5, 151) で経度 -0.002 度は -0.002 × cos(-33.5°) × 111,195.0802 = -185.448 m。
    func testSouthwestOffsetInSouthernHemisphereProjectsToNegativeValues() throws {
        let projection = GeoLocalProjection(origin: try coordinate(-33.5, 151))
        let point = projection.project(try coordinate(-33.501, 150.998))
        XCTAssertEqual(point.x, -185.448, accuracy: 0.01)
        XCTAssertEqual(point.y, -111.195_08, accuracy: 0.01)
    }

    /// 責務: 東西方向のスケールが原点の緯度で決まること(原点を北緯60度にすると半分)を確かめます。
    /// 0.001 × 0.5 × 111,195.0802 = 55.5975 m。
    func testLongitudeScaleDependsOnOriginLatitude() throws {
        let projection = GeoLocalProjection(origin: try coordinate(60, 10))
        XCTAssertEqual(projection.project(try coordinate(60, 10.001)).x, 55.5975, accuracy: 0.01)
    }

    /// 責務: `unproject(project(c))` が 1e-9 度以内に元へ戻ることを、複数の点と原点で確かめます。
    func testUnprojectOfProjectReturnsOriginalCoordinate() throws {
        let origins = [try coordinate(35, 139), try coordinate(-33.5, 151), try coordinate(0, 0), try coordinate(26.2, 127.7)]
        let offsets: [(Double, Double)] = [(0, 0), (0.001, 0.002), (-0.003, 0.004), (0.01, -0.01)]
        for origin in origins {
            let projection = GeoLocalProjection(origin: origin)
            for offset in offsets {
                let target = try coordinate(origin.latitude + offset.0, origin.longitude + offset.1)
                let restored = try XCTUnwrap(projection.unproject(projection.project(target)))
                XCTAssertEqual(restored.latitude, target.latitude, accuracy: 1e-9)
                XCTAssertEqual(restored.longitude, target.longitude, accuracy: 1e-9)
            }
        }
    }

    /// 責務: メートル単位の点から座標を作れること(北へ111.19508 m で緯度 +0.001 度)を確かめます。
    func testUnprojectOfMeterPointGivesExpectedCoordinate() throws {
        let projection = GeoLocalProjection(origin: try coordinate(35, 139))
        let restored = try XCTUnwrap(projection.unproject(GeoPlanarPoint(x: 91.085_677_288, y: 111.195_080_234)))
        XCTAssertEqual(restored.latitude, 35.001, accuracy: 1e-9)
        XCTAssertEqual(restored.longitude, 139.001, accuracy: 1e-9)
    }

    /// 責務: 結果の緯度が範囲外(北緯 89.9999 度の原点から北へ 1 km)なら `nil` になることを確かめます。
    func testUnprojectBeyondPoleReturnsNil() throws {
        let projection = GeoLocalProjection(origin: try coordinate(89.9999, 0))
        XCTAssertNil(projection.unproject(GeoPlanarPoint(x: 0, y: 1_000)))
    }

    /// 責務: 結果の経度が範囲外(東経 179.9999 度の原点から東へ 1 km)なら `nil` になることを確かめます。
    func testUnprojectBeyondAntimeridianReturnsNil() throws {
        let projection = GeoLocalProjection(origin: try coordinate(0, 179.9999))
        XCTAssertNil(projection.unproject(GeoPlanarPoint(x: 1_000, y: 0)))
    }

    /// 責務: 有限でない値(無限大・非数)を渡すと `nil` になることを確かめます。
    func testUnprojectOfNonFiniteValuesReturnsNil() throws {
        let projection = GeoLocalProjection(origin: try coordinate(35, 139))
        XCTAssertNil(projection.unproject(GeoPlanarPoint(x: .infinity, y: 0)))
        XCTAssertNil(projection.unproject(GeoPlanarPoint(x: 0, y: .nan)))
    }

    /// 責務: 極(北緯90度)の原点では東西方向に動く点が座標にならず `nil` になることを確かめます。
    func testUnprojectAtPoleOriginWithEastwardOffsetReturnsNil() throws {
        let projection = GeoLocalProjection(origin: try coordinate(90, 0))
        XCTAssertNil(projection.unproject(GeoPlanarPoint(x: 1, y: 0)))
    }
}
