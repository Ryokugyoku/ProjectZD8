import CoreLocation
import Foundation
import MapKit

/// 外接矩形 `GeoBoundingBox` から、地図に表示する範囲 `MKMapRect` を求める純粋な計算です。
///
/// 余白と最小の広がりの計算は `framedBounds(for:)` で MapKit の型を使わずに行い、
/// `mapRect(for:)` はその結果を MapKit の座標へ直すだけにしています。
nonisolated struct RouteMapFraming: Sendable {
    /// Web メルカトル図法で表せる緯度の上限(度)です。これを超える緯度は地図の座標へ直せません。
    static let mercatorLatitudeLimit = 85.051_128_78

    /// 外接矩形の各辺に足す余白の、幅・高さに対する割合です。負の値と有限でない値は 0 とみなします。
    let paddingRatio: Double
    /// 表示範囲の幅・高さの最小値(m)です。負の値と有限でない値は 0 とみなします。
    let minimumSpanMeters: Double

    /// 余白の割合と最小の広がりを指定して作ります。
    ///
    /// 責務: 受け取った値のうち、負の値と有限でない値を 0 に直して保持します。
    /// - Parameters:
    ///   - paddingRatio: 各辺に足す余白の割合。既定は `RouteMapMetrics.boundsPaddingRatio`。
    ///   - minimumSpanMeters: 幅・高さの最小値(m)。既定は `RouteMapMetrics.minimumSpanMeters`。
    init(
        paddingRatio: Double = RouteMapMetrics.boundsPaddingRatio,
        minimumSpanMeters: Double = RouteMapMetrics.minimumSpanMeters
    ) {
        self.paddingRatio = Self.nonNegative(paddingRatio)
        self.minimumSpanMeters = Self.nonNegative(minimumSpanMeters)
    }

    /// 外接矩形を地図の表示範囲へ直します。
    ///
    /// 責務: `framedBounds(for:)` の範囲を覆い、中心が元の外接矩形の中心に一致する `MKMapRect` を作ります。
    /// - Parameter bounds: 表示したい座標の外接矩形。
    /// - Returns: 地図の表示範囲。
    func mapRect(for bounds: GeoBoundingBox) -> MKMapRect {
        let framed = framedBounds(for: bounds)
        let center = MKMapPoint(Self.coordinate(latitude: Self.centerLatitude(of: bounds), longitude: Self.centerLongitude(of: bounds)))
        let northWest = MKMapPoint(Self.coordinate(latitude: framed.maxLatitude, longitude: framed.minLongitude))
        let southEast = MKMapPoint(Self.coordinate(latitude: framed.minLatitude, longitude: framed.maxLongitude))
        let halfWidth = max(center.x - northWest.x, southEast.x - center.x)
        let halfHeight = max(center.y - northWest.y, southEast.y - center.y)
        return MKMapRect(x: center.x - halfWidth, y: center.y - halfHeight, width: halfWidth * 2, height: halfHeight * 2)
    }

    /// 余白と最小の広がりを加えた範囲を、緯度・経度で返します。
    ///
    /// 責務: 元の中心を保ったまま、幅・高さを「元の幅 × (1 + 2 × 余白の割合)」と最小の広がりの大きい方にし、
    /// 緯度は Web メルカトル図法の上限、経度は -180...180 に切り詰めます。
    /// - Parameter bounds: 表示したい座標の外接矩形。
    /// - Returns: 表示する範囲。
    func framedBounds(for bounds: GeoBoundingBox) -> GeoBoundingBox {
        let centerLatitude = Self.centerLatitude(of: bounds)
        let centerLongitude = Self.centerLongitude(of: bounds)
        let latitudeHalfSpan = halfSpan(
            span: bounds.maxLatitude - bounds.minLatitude,
            minimumDegrees: minimumSpanMeters / GeoBoundingBox.metersPerDegree
        )
        let longitudeHalfSpan = halfSpan(
            span: bounds.maxLongitude - bounds.minLongitude,
            minimumDegrees: Self.longitudeDegrees(meters: minimumSpanMeters, atLatitude: centerLatitude)
        )
        let limit = Self.mercatorLatitudeLimit
        return GeoBoundingBox(
            minLatitude: Self.clamp(centerLatitude - latitudeHalfSpan, to: -limit...limit),
            maxLatitude: Self.clamp(centerLatitude + latitudeHalfSpan, to: -limit...limit),
            minLongitude: Self.clamp(centerLongitude - longitudeHalfSpan, to: -180...180),
            maxLongitude: Self.clamp(centerLongitude + longitudeHalfSpan, to: -180...180)
        ) ?? bounds
    }

    /// 1軸の表示範囲の半分の幅を返します。
    ///
    /// 責務: 余白を加えた幅と最小の幅の大きい方を半分にします。
    /// - Parameters:
    ///   - span: 元の幅(度)。
    ///   - minimumDegrees: 最小の幅(度)。
    /// - Returns: 半分の幅(度)。
    private func halfSpan(span: Double, minimumDegrees: Double) -> Double {
        max(span * (1 + paddingRatio * 2), minimumDegrees) / 2
    }

    /// 指定した緯度で、距離を経度の差へ直します。
    ///
    /// 責務: cos(緯度) が 0 に近く有限の値が得られない時は、全範囲(360 度)を返します。
    /// - Parameters:
    ///   - meters: 距離(m)。
    ///   - latitude: 基準の緯度(度)。
    /// - Returns: 経度の差(度)。
    private static func longitudeDegrees(meters: Double, atLatitude latitude: Double) -> Double {
        let degrees = meters / (GeoBoundingBox.metersPerDegree * cos(latitude * Double.pi / 180))
        return degrees.isFinite && degrees >= 0 ? min(degrees, 360) : 360
    }

    /// 外接矩形の中心の緯度を返します。
    ///
    /// 責務: 南端と北端の中点を、Web メルカトル図法の上限に切り詰めて返します。
    /// - Parameter bounds: 外接矩形。
    /// - Returns: 中心の緯度(度)。
    private static func centerLatitude(of bounds: GeoBoundingBox) -> Double {
        clamp((bounds.minLatitude + bounds.maxLatitude) / 2, to: -mercatorLatitudeLimit...mercatorLatitudeLimit)
    }

    /// 外接矩形の中心の経度を返します。
    ///
    /// 責務: 西端と東端の中点を返します。
    /// - Parameter bounds: 外接矩形。
    /// - Returns: 中心の経度(度)。
    private static func centerLongitude(of bounds: GeoBoundingBox) -> Double {
        (bounds.minLongitude + bounds.maxLongitude) / 2
    }

    /// 値を範囲へ切り詰めます。
    ///
    /// 責務: 範囲の外の値を近い方の端へ寄せます。
    /// - Parameters:
    ///   - value: 切り詰める値。
    ///   - range: 許す範囲。
    /// - Returns: 範囲内の値。
    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// 負の値と有限でない値を 0 に直します。
    ///
    /// 責務: 設定値として使えない値を 0 に置き換えます。
    /// - Parameter value: 直す値。
    /// - Returns: 0 以上の有限の値。
    private static func nonNegative(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    /// 緯度・経度から MapKit の座標を作ります。
    ///
    /// 責務: 検査済みの度の値を `CLLocationCoordinate2D` へ詰めます。
    /// - Parameters:
    ///   - latitude: 緯度(度)。
    ///   - longitude: 経度(度)。
    /// - Returns: MapKit の座標。
    private static func coordinate(latitude: Double, longitude: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
