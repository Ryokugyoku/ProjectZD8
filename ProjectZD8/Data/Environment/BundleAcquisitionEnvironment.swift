import Foundation

/// バンドル情報と端末の機種情報から取得環境を組み立てます。
nonisolated struct BundleAcquisitionEnvironment: AcquisitionEnvironmentPort {
    /// インストールIDの保存キーです。
    static let installationIDKey = "insight.installationID"
    /// バンドルから版情報を読めない場合の表示値です。
    static let unknownVersion = "unknown"

    private static let installationLock = NSLock()

    private let bundle: Bundle
    /// UserDefaultsはスレッドセーフなので、Sendableでない型でも安全に共有できます。
    private nonisolated(unsafe) let defaults: UserDefaults
    private let modelIdentifier: String

    /// 責務: バンドル・インストールID保存先・機種識別子を指定して生成します。機種識別子は端末のユーザー設定名ではなくモデル名です。
    init(bundle: Bundle = .main, defaults: UserDefaults = .standard, modelIdentifier: String = BundleAcquisitionEnvironment.currentModelIdentifier()) {
        self.bundle = bundle
        self.defaults = defaults
        self.modelIdentifier = modelIdentifier
    }

    /// 責務: 現在のアプリ版・端末種別・インストールIDを返します。
    func environment() -> AcquisitionEnvironment {
        AcquisitionEnvironment(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? Self.unknownVersion,
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? Self.unknownVersion,
            platform: platform(),
            deviceID: installationID(),
            deviceName: modelIdentifier
        )
    }

    /// 責務: 機種識別子から端末種別を決めます。
    private func platform() -> AcquisitionPlatform {
        #if os(macOS)
        return .mac
        #else
        return modelIdentifier.hasPrefix("iPad") ? .iPad : .iPhone
        #endif
    }

    /// 責務: 保存済みのインストールIDを返し、無ければ生成して保存します。
    private func installationID() -> String {
        Self.installationLock.lock()
        defer { Self.installationLock.unlock() }
        if let stored = defaults.string(forKey: Self.installationIDKey), !stored.isEmpty { return stored }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: Self.installationIDKey)
        return created
    }

    /// 責務: 実行中の機種識別子(例: `iPhone16,1`、`Mac15,6`)を返します。シミュレーターでは模擬している機種を返します。
    static func currentModelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        #if os(macOS)
        let name = "hw.model"
        #else
        let name = "hw.machine"
        #endif
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }
}
