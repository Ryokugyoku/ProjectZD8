import Foundation

/// 地球上の1点を緯度・経度(度)で表します。値は常に有限で、緯度 -90...90、経度 -180...180 に収まります。
nonisolated struct GeoCoordinate: Hashable, Sendable {
    /// 緯度(度)。北が正です。
    let latitude: Double
    /// 経度(度)。東が正です。
    let longitude: Double

    /// 緯度・経度を検査して座標を作ります。
    ///
    /// 責務: 有限で範囲内の緯度・経度だけを座標として受け入れます。
    /// - Parameters:
    ///   - latitude: 緯度(度)。有限かつ -90...90。
    ///   - longitude: 経度(度)。有限かつ -180...180。
    /// - Returns: どちらかが範囲外または有限でなければ `nil`。
    init?(latitude: Double, longitude: Double) {
        guard Self.isValidLatitude(latitude), Self.isValidLongitude(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    /// 緯度として使える値かを返します。
    ///
    /// 責務: 有限かつ -90...90 であることを判定します。
    /// - Parameter value: 調べる緯度。
    /// - Returns: 使える値なら `true`。
    static func isValidLatitude(_ value: Double) -> Bool {
        value.isFinite && (-90.0...90.0).contains(value)
    }

    /// 経度として使える値かを返します。
    ///
    /// 責務: 有限かつ -180...180 であることを判定します。
    /// - Parameter value: 調べる経度。
    /// - Returns: 使える値なら `true`。
    static func isValidLongitude(_ value: Double) -> Bool {
        value.isFinite && (-180.0...180.0).contains(value)
    }
}
