import CoreLocation
import MapKit
import XCTest
@testable import ProjectZD8

/// `RouteMapFraming.mapRect(for:)` が余白込みの範囲を覆い、中心が元の外接矩形の中心になることを検証します。
@MainActor
final class RouteMapFramingMapRectTests: XCTestCase {
    /// 責務: 4辺から外接矩形を作ります(無効ならテストの誤りとして失敗させます)。
    private func box(_ minLat: Double, _ maxLat: Double, _ minLon: Double, _ maxLon: Double) throws -> GeoBoundingBox {
        try XCTUnwrap(GeoBoundingBox(minLatitude: minLat, maxLatitude: maxLat, minLongitude: minLon, maxLongitude: maxLon))
    }

    /// 責務: `mapRect` が余白込みの範囲の4隅を覆い、中心が元の外接矩形の中心であることを確かめます。
    func testMapRectCoversFramedBoundsAroundOriginalCenter() throws {
        let source = try box(26.0, 26.02, 127.6, 127.64)
        let framing = RouteMapFraming()
        let rect = framing.mapRect(for: source).insetBy(dx: -1, dy: -1)
        let framed = framing.framedBounds(for: source)
        for (lat, lon) in [(framed.minLatitude, framed.minLongitude), (framed.maxLatitude, framed.maxLongitude),
                           (framed.minLatitude, framed.maxLongitude), (framed.maxLatitude, framed.minLongitude)] {
            XCTAssertTrue(rect.contains(MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon))))
        }
        let center = MKMapPoint(CLLocationCoordinate2D(latitude: 26.01, longitude: 127.62))
        XCTAssertEqual(framing.mapRect(for: source).midX, center.x, accuracy: 1e-3)
        XCTAssertEqual(framing.mapRect(for: source).midY, center.y, accuracy: 1e-3)
    }

    /// 責務: 1点だけの外接矩形でも、`mapRect` が正の幅・高さを持ち、ほぼ 400 m 以上(MapKit は楕円体、製品は球の換算のため約0.4%の差があり、390 m で判定)であることを確かめます。
    func testMapRectOfSinglePointHasPositiveSize() throws {
        let rect = RouteMapFraming().mapRect(for: try box(26.2, 26.2, 127.7, 127.7))
        let metersPerPoint = 1 / MKMapPointsPerMeterAtLatitude(26.2)
        XCTAssertGreaterThanOrEqual(rect.width * metersPerPoint, 390)
        XCTAssertGreaterThanOrEqual(rect.height * metersPerPoint, 390)
    }
}
