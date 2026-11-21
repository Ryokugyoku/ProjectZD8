import CoreLocation
import Foundation

/// CoreLocation の許可状態と精度許可を Domain の `LocationPermission` へ変換します。
nonisolated struct CoreLocationPermissionMapper: Sendable {
    /// `kCLAuthorizationStatusAuthorizedWhenInUse` の値です。
    ///
    /// この値は macOS SDK では利用不可と宣言されているため、`#if` を使わず両 OS で同じ判定にするよう値で比べます。
    private static let authorizedWhenInUseRawValue: Int32 = 4

    /// 状態を持たない変換器を生成します。
    ///
    /// 責務: 変換器を構築します。
    init() {}

    /// 許可状態と精度許可を `LocationPermission` へ変換します。
    ///
    /// 責務: 許可の段階を対応づけ、正確な位置の許可を `fullAccuracy` かどうかで決めます。
    /// - Parameters:
    ///   - status: CoreLocation の許可状態。
    ///   - accuracy: CoreLocation の精度許可。
    /// - Returns: Domain の許可状態。
    func permission(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) -> LocationPermission {
        LocationPermission(level: level(for: status), isPreciseAccuracy: accuracy == .fullAccuracy)
    }

    /// 許可状態を許可の段階へ変換します。
    ///
    /// 責務: 既知の状態を対応する段階へ写し、未知の状態は `.denied` にします。
    /// 未知の状態を取得可能な段階や「未確定」にすると、許可が無いのに取得を試みたり許可を要求し直したりして
    /// 失敗を成功に見せるおそれがあるため、取得しない側の `.denied` に倒します。
    /// macOS の `authorized` は `authorizedAlways` と同じ値なので `.always` になります。
    /// - Parameter status: CoreLocation の許可状態。
    /// - Returns: 許可の段階。
    private func level(for status: CLAuthorizationStatus) -> LocationAuthorizationLevel {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorizedAlways:
            return .always
        default:
            return Self.isAuthorizedWhenInUse(status) ? .whenInUse : .denied
        }
    }

    /// 「使用中のみ」の許可かを返します。
    ///
    /// 責務: 許可状態の値を `kCLAuthorizationStatusAuthorizedWhenInUse` と比べます。
    /// - Parameter status: CoreLocation の許可状態。
    /// - Returns: 「使用中のみ」なら `true`。
    private static func isAuthorizedWhenInUse(_ status: CLAuthorizationStatus) -> Bool {
        status.rawValue == authorizedWhenInUseRawValue
    }
}
