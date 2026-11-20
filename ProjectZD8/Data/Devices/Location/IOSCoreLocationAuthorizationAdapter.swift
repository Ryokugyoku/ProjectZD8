#if os(iOS)
import CoreLocation
import Foundation

/// 位置情報の利用許可を読み取り・要求する iOS 用のアダプターです。取得用とは別の `CLLocationManager` を持ちます。
///
/// manager はメインスレッドで作るため、delegate もメインスレッドで呼ばれます(`AppleCoreBluetoothCentralRole` と同じ流儀)。
@MainActor
final class IOSCoreLocationAuthorizationAdapter: NSObject, LocationAuthorizationPort, CLLocationManagerDelegate {
    /// 許可の読み取りと要求に使う manager です。
    private let manager = CLLocationManager()
    /// 許可状態の変換器です。
    private let mapper = CoreLocationPermissionMapper()
    /// 許可状態の流れの送り口です。消費者は1つだけなので、新しい流れを作ると置き換えます。
    private var continuation: AsyncStream<LocationPermission>.Continuation?

    /// 許可の manager を生成します。
    ///
    /// 責務: 許可の変化を受け取れるよう manager の delegate を自分に設定します。
    override init() {
        super.init()
        manager.delegate = self
    }

    /// 現在の許可状態。
    var currentPermission: LocationPermission {
        mapper.permission(status: manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
    }

    /// 許可状態の変化の流れを返します。
    ///
    /// 責務: 前の流れを終えて新しい流れを1つだけ有効にし、許可が変わるたびに現在の状態を流します。
    /// - Returns: 許可状態の流れ。
    func permissionChanges() -> AsyncStream<LocationPermission> {
        continuation?.finish()
        let (stream, continuation) = AsyncStream<LocationPermission>.makeStream()
        self.continuation = continuation
        return stream
    }

    /// 「使用中のみ」の許可を要求します。
    ///
    /// 責務: manager の `requestWhenInUseAuthorization()` を呼びます。
    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// 「常に許可」を要求します。
    ///
    /// 責務: manager の `requestAlwaysAuthorization()` を呼びます。
    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// 許可の変化を流れへ送ります。
    ///
    /// 責務: 許可が変わるたびに現在の許可状態を流します。
    /// - Parameter manager: 許可が変わった manager。
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        continuation?.yield(currentPermission)
    }
}
#endif
