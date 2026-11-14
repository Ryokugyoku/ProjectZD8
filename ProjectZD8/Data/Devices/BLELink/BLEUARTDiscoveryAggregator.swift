#if os(iOS) || os(macOS)
/// Service探索とService別Characteristic探索の結果を集め、全Service分そろったらUART送受信路を解決します。
nonisolated struct BLEUARTDiscoveryAggregator: Sendable {
    /// 探索結果を照合する既知UART構成です。
    private let profiles: [AppleBluetoothUARTProfile]
    /// Characteristic探索の完了を待っているService UUIDです。
    private(set) var pendingServiceUUIDs: Set<String> = []
    /// Service UUIDごとに集めたCharacteristic能力です。
    private var capabilitiesByService: [String: [AppleBluetoothCharacteristicCapability]] = [:]
    /// Service探索結果を受け取ったかどうかです。
    private(set) var hasServiceList = false

    /// 照合する既知UART構成を固定して生成します。
    ///
    /// 責務: 解決に使う既知UART構成を保持します。
    /// - Parameter profiles: 優先順に照合する既知UART構成。
    init(profiles: [AppleBluetoothUARTProfile] = AppleBluetoothUARTProfile.supported) {
        self.profiles = profiles
    }

    /// 全ServiceのCharacteristic探索がそろったかどうかです。
    var isComplete: Bool { hasServiceList && pendingServiceUUIDs.isEmpty }

    /// Service探索結果を記録し、Characteristic探索が必要なService UUIDを返します。
    ///
    /// 責務: 発見Service一覧を大文字・重複なしの待機集合へ変換し、以前の集計を捨てます。
    /// - Parameter serviceUUIDs: 発見したService UUID。
    /// - Returns: Characteristic探索を要求するService UUID(発見順、重複なし、大文字)。
    mutating func beginServices(_ serviceUUIDs: [String]) -> [String] {
        var ordered: [String] = []
        for uuid in serviceUUIDs.map({ $0.uppercased() }) where !ordered.contains(uuid) {
            ordered.append(uuid)
        }
        hasServiceList = true
        pendingServiceUUIDs = Set(ordered)
        capabilitiesByService = [:]
        return ordered
    }

    /// 1件のServiceのCharacteristic能力を記録します。
    ///
    /// 責務: 待機中のServiceだけを完了扱いにして能力を集めます。
    /// - Parameters:
    ///   - serviceUUID: 探索したService UUID。
    ///   - capabilities: 発見したCharacteristic能力。
    /// - Returns: 待機中のServiceとして受け付けた場合は `true`。重複・未要求のServiceは `false`。
    mutating func recordCharacteristics(
        serviceUUID: String,
        capabilities: [AppleBluetoothCharacteristicCapability]
    ) -> Bool {
        let key = serviceUUID.uppercased()
        guard pendingServiceUUIDs.remove(key) != nil else { return false }
        capabilitiesByService[key] = capabilities
        return true
    }

    /// 集めた能力から送受信路を解決します。
    ///
    /// 責務: 全Service分そろった能力を既知UART構成と書き込み種別へ解決します。
    /// - Returns: 解決した送受信路。未完了または一致する構成がなければ `nil`。
    func resolveChannel() -> BLEResolvedUARTChannel? {
        guard isComplete,
              let profile = AppleBluetoothUARTProfileResolver().resolve(services: capabilitiesByService, profiles: profiles),
              let writeCapability = capabilitiesByService[profile.serviceUUID]?.first(where: {
                  $0.uuid == profile.writeCharacteristicUUID
              }) else {
            return nil
        }
        return BLEResolvedUARTChannel.make(profile: profile, writeCapability: writeCapability)
    }
}
#endif
