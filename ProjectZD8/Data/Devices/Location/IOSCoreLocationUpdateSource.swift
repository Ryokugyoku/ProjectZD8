#if os(iOS)
import CoreLocation
import Foundation

/// 1つの `CLLocationManager` を位置の取得元として包む iOS 用のアダプターです。
///
/// 同時に有効な流れは1つだけです。流れがある間だけ取得し、流れが終わったら取得を止めて背面での取得を解除します。
/// manager はメインスレッドで作るため、delegate もメインスレッドで呼ばれます(`AppleCoreBluetoothCentralRole` と同じ流儀)。
@MainActor
final class IOSCoreLocationUpdateSource: NSObject, LocationUpdateSourcePort, CLLocationManagerDelegate {
    /// 受信時の単調時計です。
    private let clock: any MonotonicClockPort
    /// `CLLocation` を `LocationFix` へ変換する変換器です。
    private let mapper: CoreLocationFixMapper
    /// このアダプターが生成した位置取得の manager です。
    private let manager = CLLocationManager()
    /// 現在有効な流れの送り口です。流れが無い間は `nil` です。
    private var continuation: AsyncStream<LocationUpdateEvent>.Continuation?
    /// 現在有効な流れの識別子です。終了済みの古い流れからの通知を無視するために使います。
    private var activeStreamID: UUID?

    /// 時計と変換器を注入して取得元を生成します。
    ///
    /// 責務: manager の取得設定(車載ナビ向け・最高精度・距離間引きなし・自動停止なし・背面表示なし)を固定します。
    /// - Parameters:
    ///   - clock: 受信時の単調時計。
    ///   - mapper: `CLLocation` の変換器。
    init(clock: any MonotonicClockPort = ContinuousMonotonicClock(), mapper: CoreLocationFixMapper = .init()) {
        self.clock = clock
        self.mapper = mapper
        super.init()
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
        manager.delegate = self
    }

    /// 位置の流れを作り、取得を始めます。
    ///
    /// 責務: 前の流れがあれば終えてから新しい流れを1つだけ有効にし、背面許可を見直して取得を始めます。
    /// - Returns: 位置または取得不可の通知の流れ。
    func makeUpdates() -> AsyncStream<LocationUpdateEvent> {
        continuation?.finish()
        let streamID = UUID()
        let (stream, continuation) = AsyncStream<LocationUpdateEvent>.makeStream()
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.streamDidTerminate(streamID)
            }
        }
        self.continuation = continuation
        activeStreamID = streamID
        updateBackgroundLocationUpdates()
        manager.startUpdatingLocation()
        return stream
    }

    /// 流れの終了を受けて取得を止めます。
    ///
    /// 責務: 現在有効な流れの終了だけを扱い、取得を止めて背面での取得を解除します。
    /// - Parameter streamID: 終了した流れの識別子。
    private func streamDidTerminate(_ streamID: UUID) {
        guard activeStreamID == streamID else { return }
        activeStreamID = nil
        continuation = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    /// 背面での取得の可否を見直します。
    ///
    /// 責務: 流れがあり、許可が「常に」の時だけ背面での取得を有効にします。
    private func updateBackgroundLocationUpdates() {
        manager.allowsBackgroundLocationUpdates = continuation != nil && manager.authorizationStatus == .authorizedAlways
    }

    /// 受け取った位置を流れへ送ります。
    ///
    /// 責務: 各位置を変換し、変換できたものだけを `.fix` として流します。
    /// - Parameters:
    ///   - manager: 位置を届けた manager。
    ///   - locations: 届いた位置(古い順)。
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation else { return }
        let wallNow = Date()
        let monotonicNow = clock.nowNanoseconds()
        for location in locations {
            guard let fix = mapper.fix(from: location, wallNow: wallNow, monotonicNow: monotonicNow) else { continue }
            continuation.yield(.fix(fix))
        }
    }

    /// 取得の失敗を流れへ送ります。
    ///
    /// 責務: 失敗を取得不可の通知へ変換して流します。拒否は許可の側が扱うので流しません。
    /// - Parameters:
    ///   - manager: 失敗を届けた manager。
    ///   - error: 取得の失敗。
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard let event = Self.unavailableEvent(for: error) else { return }
        continuation?.yield(event)
    }

    /// 許可の変化を受けて背面での取得を見直します。
    ///
    /// 責務: 取得中に許可が「常に」へ変わった場合も背面での取得を有効にできるよう見直します。
    /// - Parameter manager: 許可が変わった manager。
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateBackgroundLocationUpdates()
    }

    /// 取得の失敗を取得不可の通知へ変換します。
    ///
    /// 責務: `kCLErrorLocationUnknown` を一時的な取得不可、`kCLErrorDenied` を通知なし、それ以外を失敗にします。
    /// - Parameter error: 取得の失敗。
    /// - Returns: 流す通知。流さない場合は `nil`。
    private static func unavailableEvent(for error: any Error) -> LocationUpdateEvent? {
        guard let locationError = error as? CLError else { return .unavailable(.failed) }
        switch locationError.code {
        case .locationUnknown:
            return .unavailable(.temporarilyUnavailable)
        case .denied:
            return nil
        default:
            return .unavailable(.failed)
        }
    }
}
#endif
