import Foundation

/// `UserDefaults` を使って「エンジン停止とみなす時間」を端末ローカルに保持します(iCloudへは同期しません)。
nonisolated final class UserDefaultsVehicleOffDetectionDelayStore: VehicleOffDetectionDelayPreferencePort {
    /// 設定を保存する `UserDefaults` です。
    private let defaults: UserDefaults
    /// 設定を識別するキーです。
    private let key: String

    /// 保存先とキーを注入してストアを生成します。
    ///
    /// 責務: 設定の保存先を1件の `UserDefaults` キーへ固定します。
    /// - Parameters:
    ///   - defaults: 設定を保存する `UserDefaults`。
    ///   - key: 設定を識別するキー。
    init(
        defaults: UserDefaults = .standard,
        key: String = "deviceConnection.vehicleOffDetectionDelaySeconds"
    ) {
        self.defaults = defaults
        self.key = key
    }

    /// 保存済みの時間を読み込みます。
    ///
    /// 責務: 保存済みの秒数を返し、未保存・整数でない値・選択肢にない秒数は既定の30秒として扱います。
    /// - Returns: 保存済みの時間。
    func load() -> VehicleOffDetectionDelay {
        guard let seconds = defaults.object(forKey: key) as? Int else { return .standard }
        return VehicleOffDetectionDelay(rawValue: seconds) ?? .standard
    }

    /// 時間を保存します。
    ///
    /// 責務: 1件の秒数を置き換えて保存します。
    /// - Parameter delay: 保存する時間。
    func save(_ delay: VehicleOffDetectionDelay) {
        defaults.set(delay.rawValue, forKey: key)
    }
}
