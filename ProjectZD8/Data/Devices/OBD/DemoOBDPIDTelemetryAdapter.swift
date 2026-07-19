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
        switch pid {
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
        case 0x2C: [77]
        case 0x2D: [128]
        case 0x2E: [38]
        case 0x2F: [166]
        case 0x30: [2]
        case 0x31: twoBytes(120)
        case 0x32: [0x80, 0x00]
        case 0x33: [100]
        case 0x3C...0x3F: twoBytes(4_900)
        case 0x42: twoBytes(14_200)
        case 0x43: twoBytes(64 + Int(speed) * 2)
        case 0x44: [0x80, 0x00]
        case 0x45, 0x47, 0x48: [UInt8(clamping: 40 + Int(speed))]
        case 0x46: [65]
        case 0x49...0x4C: [UInt8(clamping: 35 + Int(speed))]
        case 0x4D: [0, 0]
        case 0xA6: [0x00, 0x01, 0xE2, 0x40]
        default: nil
        }
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
}
