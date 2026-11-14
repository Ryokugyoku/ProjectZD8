/// ECUへService 01の対応PIDビットマップ(PID 00/20/40…)を問い合わせ、対応を返した標準PIDを求めます。
struct DiscoverSupportedStandardPIDsUseCase: Sendable {
    /// 対応PIDビットマップを読み取る取得境界です。
    private let telemetry: any OBDPIDTelemetryPort

    /// 取得境界を固定します。
    ///
    /// 責務: 対応PID探索を物理PID取得境界へ結び付けます。
    /// - Parameter telemetry: 対応PIDビットマップを読み取る取得境界。
    init(telemetry: any OBDPIDTelemetryPort) {
        self.telemetry = telemetry
    }

    /// 対応PIDビットマップを順に読み、対応が示された標準PIDを返します。
    ///
    /// 責務: PID 00から始めて次のビットマップの対応ビットが立つ間だけ問い合わせを続け、ビットマップ用PIDを除いて返します。
    /// - Parameter endpoint: OBDアダプターの物理終端。
    /// - Returns: ECUが対応を返したService 01 PID。
    /// - Throws: ビットマップの応答が無い・短い場合は `OBDPIDTelemetryError.noVehicleResponse`、取得境界の失敗。
    func execute(using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest] {
        var supported: [OBDPIDRequest] = []
        var base: UInt8 = 0x00
        while base <= 0xE0 {
            let query = OBDPIDRequest(service: 0x01, pid: base)
            let response = try await telemetry.read([query], using: endpoint)
            guard let bytes = response[query], bytes.count >= 4 else {
                throw OBDPIDTelemetryError.noVehicleResponse
            }
            for offset in 1...32 where Self.bitIsSet(offset: offset, bytes: bytes) {
                let value = Int(base) + offset
                guard value <= 0xFF, value % 0x20 != 0 else { continue }
                supported.append(OBDPIDRequest(service: 0x01, pid: UInt8(value)))
            }
            guard Self.bitIsSet(offset: 32, bytes: bytes), base < 0xE0 else { break }
            base &+= 0x20
        }
        return supported
    }

    /// ビットマップの指定位置が立っているかを返します。
    ///
    /// 責務: 1始まりのビット位置を先頭バイトの最上位ビットから数えて判定します。
    /// - Parameters:
    ///   - offset: 1から32のビット位置。
    ///   - bytes: 4バイト以上のビットマップ。
    /// - Returns: 立っていれば `true`。
    private static func bitIsSet(offset: Int, bytes: [UInt8]) -> Bool {
        let zeroBased = offset - 1
        return bytes[zeroBased / 8] & (0x80 >> UInt8(zeroBased % 8)) != 0
    }
}
