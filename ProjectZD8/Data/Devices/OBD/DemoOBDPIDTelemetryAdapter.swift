import Foundation

/// 実走行に近い相関を持つ決定的なデモPID応答を生成します。
@MainActor
final class DemoOBDPIDTelemetryAdapter: OBDPIDTelemetryPort {
    /// 連続する観測値を進行させる更新番号です。
    private var tick: UInt64 = 0

    /// 空のデモ走行状態を生成します。
    ///
    /// 責務: デモPID応答の更新番号を初期値へ設定します。
    init() {}

    /// 指定PID群へ物理通信なしの応答バイトを返します。
    ///
    /// 責務: 1回のデモ読取要求を相関した走行状態の未加工PIDバイトへ変換します。
    /// - Parameters:
    ///   - requests: PID定義DBから選ばれたService/PID要求。
    ///   - endpoint: デモOBD接続終端。
    /// - Returns: 要求ごとの決定的な未加工応答バイト。
    /// - Throws: デモ以外の終端では `OBDPIDTelemetryError.unavailable`。
    func read(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        guard DemoOBDAdapter.matches(endpoint) else { throw OBDPIDTelemetryError.unavailable }
        tick &+= 1
        let phase = Double(tick % 160) / 160.0
        let speed = UInt8(clamping: Int((sin(phase * .pi) * 92).rounded()))
        let rpm = max(760, Int(speed) * 38 + 820 + Int(tick % 9) * 12)
        let coolant = min(92, 72 + Int(tick / 12))
        var values: [OBDPIDRequest: [UInt8]] = [:]
        for request in requests where request.service == 0x01 {
            switch request.pid {
            case 0x04:
                values[request] = [UInt8(clamping: 28 + Int(speed) * 2)]
            case 0x05:
                values[request] = [UInt8(clamping: coolant + 40)]
            case 0x0C:
                let encoded = UInt16(clamping: rpm * 4)
                values[request] = [UInt8(encoded >> 8), UInt8(encoded & 0xFF)]
            case 0x0D:
                values[request] = [speed]
            case 0x11:
                values[request] = [UInt8(clamping: 22 + Int(speed) * 2)]
            default:
                let base = UInt8(truncatingIfNeeded: Int(request.pid) * 17 + Int(tick))
                values[request] = (0..<8).map { base &+ UInt8($0 * 7) }
            }
        }
        return values
    }
}
