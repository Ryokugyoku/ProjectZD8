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
            values[request] = responseBytes(pid: request.pid, speed: speed, rpm: rpm, coolant: coolant)
        }
        return values
    }

    /// デモ走行状態を指定PIDの正常域バイトへ符号化します。
    ///
    /// 責務: 1件の主要Service 01 PIDを決定的な合成応答バイトへ変換します。
    /// - Parameters:
    ///   - pid: 応答するService 01 PID番号。
    ///   - speed: 現在の合成車速。
    ///   - rpm: 現在の合成エンジン回転数。
    ///   - coolant: 現在の合成冷却水温。
    /// - Returns: 登録済み主要PIDでは正常域の応答バイト、未登録PIDでは `nil`。
    private func responseBytes(pid: UInt8, speed: UInt8, rpm: Int, coolant: Int) -> [UInt8]? {
        if pid % 0x20 == 0 { return supportedPIDBitmap(base: pid) }
        return switch pid {
        case 0x04: [UInt8(clamping: 55 + Int(speed))]
        case 0x05: [UInt8(clamping: coolant + 40)]
        case 0x06...0x09: [128]
        case 0x0A: [100]
        case 0x0B: [42]
        case 0x0C: twoBytes(rpm * 4)
        case 0x0D: [speed]
        case 0x0E: [148]
        case 0x0F: [70]
        case 0x10: twoBytes(1_200 + Int(speed) * 18)
        case 0x11: [UInt8(clamping: 42 + Int(speed))]
        case 0x14...0x1B: [140, 128]
        case 0x1F: twoBytes(Int(tick % 3_600))
        case 0x21: [0, 0]
        case 0x22: twoBytes(3_797)
        case 0x23: twoBytes(400)
        case 0x24...0x2B: [0x80, 0x00, 0x00, 0x00]
        case 0x2C: [77]
        case 0x2D: [128]
        case 0x2E: [38]
        case 0x2F: [166]
        case 0x30: [2]
        case 0x31: twoBytes(120)
        case 0x32: [0x80, 0x00]
        case 0x33: [100]
        case 0x34...0x3B: [0x80, 0x00, 0x00, 0x00]
        case 0x3C...0x3F: twoBytes(4_900)
        case 0x42: twoBytes(14_200)
        case 0x43: twoBytes(64 + Int(speed) * 2)
        case 0x44: [0x80, 0x00]
        case 0x45, 0x47, 0x48: [UInt8(clamping: 40 + Int(speed))]
        case 0x46: [65]
        case 0x49...0x4C: [UInt8(clamping: 35 + Int(speed))]
        case 0x4D: [0, 0]
        case 0x4E: [0, 0]
        case 0x50: [20]
        case 0x52: [128]
        case 0x53: [0x27, 0x10]
        case 0x54: [0x7F, 0xFF]
        case 0x59: [0x01, 0x90]
        case 0x5A, 0x5B: [128]
        case 0x5C: [120]
        case 0x5D: [0x6E, 0x00]
        case 0x5E: [0x00, 0xC8]
        case 0x61, 0x62: [125]
        case 0x63: [0x01, 0x90]
        case 0x7C: [0x11, 0x30]
        case 0x8D: [128]
        case 0x8E: [125]
        case 0xA2: [0x01, 0x00]
        case 0xA4: [0x00, 0x00, 0x03, 0xE8]
        case 0xA5: [0x00, 0x80]
        case 0xA6: fourBytes(123_456 + tick / 10)
        default: nil
        }
    }

    /// デモが数値化して返せるPIDをService 01対応ビットマップへ符号化します。
    ///
    /// 責務: 1件の0x20刻み範囲先頭を4バイトの対応PIDビットマップへ変換します。
    /// - Parameter base: 00、20、40以降の範囲先頭PID。
    /// - Returns: 範囲内の数値化可能PIDと後続範囲有無を示す4バイト。
    private func supportedPIDBitmap(base: UInt8) -> [UInt8] {
        let supported = Set(StandardOBDPIDSeed.definitions.filter(\.isDecodable).map(\.pid))
        var bytes = [UInt8](repeating: 0, count: 4)
        for offset in 1...32 {
            let value = Int(base) + offset
            let hasPID = value <= 0xFF && supported.contains(UInt8(value))
            let hasLaterRange = offset == 32 && supported.contains { Int($0) > Int(base) + 32 }
            guard hasPID || hasLaterRange else { continue }
            let zeroBased = offset - 1
            bytes[zeroBased / 8] |= 0x80 >> UInt8(zeroBased % 8)
        }
        return bytes
    }

    /// 非負整数を上位バイト優先の2バイトへ符号化します。
    ///
    /// 責務: 1件のデモ用整数をUInt16範囲へ制限した未加工バイトへ変換します。
    /// - Parameter value: 符号化する非負整数。
    /// - Returns: 上位、下位の順に並ぶ2バイト。
    private func twoBytes(_ value: Int) -> [UInt8] {
        let encoded = UInt16(clamping: value)
        return [UInt8(encoded >> 8), UInt8(encoded & 0xFF)]
    }

    /// 非負整数を上位バイト優先の4バイトへ符号化します。
    ///
    /// 責務: 1件のデモ用累積値をUInt32範囲へ制限した未加工バイトへ変換します。
    /// - Parameter value: 符号化する非負整数。
    /// - Returns: 上位から下位の順に並ぶ4バイト。
    private func fourBytes(_ value: UInt64) -> [UInt8] {
        let encoded = UInt32(clamping: value)
        return [
            UInt8(encoded >> 24),
            UInt8((encoded >> 16) & 0xFF),
            UInt8((encoded >> 8) & 0xFF),
            UInt8(encoded & 0xFF)
        ]
    }
}
