/// BRZ Beta周期取得で使用する標準OBD現在値を限定します。
struct BRZBetaPIDPolicy {
    /// エンジン回転数と車速の読取り専用要求です。
    static let requests: [OBDPIDRequest] = [
        OBDPIDRequest(service: 0x01, pid: 0x0C),
        OBDPIDRequest(service: 0x01, pid: 0x0D)
    ]

    /// 対応確認済み定義からBetaに必要な2件を順序通り選びます。
    ///
    /// 責務: 対応PID定義一覧を回転数と車速が揃ったBeta取得対象へ変換します。
    /// - Parameter definitions: 車両の対応ビットマップと収集設定を通過したPID定義。
    /// - Returns: 2件が揃う場合は回転数、車速順の定義、欠ける場合は `nil`。
    func definitions(from definitions: [OBDPIDDefinition]) -> [OBDPIDDefinition]? {
        let definitionsByRequest = Dictionary(uniqueKeysWithValues: definitions.map { ($0.request, $0) })
        let selected = Self.requests.compactMap { definitionsByRequest[$0] }
        return selected.count == Self.requests.count ? selected : nil
    }
}

/// PID定義から読取要求を復元します。
private extension OBDPIDDefinition {
    /// この定義が表すService/PID要求です。
    var request: OBDPIDRequest { OBDPIDRequest(service: service, pid: pid) }
}
