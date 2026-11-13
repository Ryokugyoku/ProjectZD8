import Foundation

/// 接続直後に車両とアダプターから読み取った識別情報です。
nonisolated struct VehicleIdentification: Equatable, Sendable {
    /// 車両が返したVINです。読み取れなかった場合は `nil` です。
    let vin: String?
    /// アダプターの製品情報(ATI応答)です。
    let adapterDescription: String
    /// 車両との通信プロトコル(ATDP応答)です。
    let protocolDescription: String
    /// 読み取った日時です。
    let observedAt: Date

    /// 識別情報を生成します。
    ///
    /// 責務: 1回の接続で読み取った識別値をまとめます。
    init(vin: String?, adapterDescription: String, protocolDescription: String, observedAt: Date) {
        self.vin = vin
        self.adapterDescription = adapterDescription
        self.protocolDescription = protocolDescription
        self.observedAt = observedAt
    }
}
