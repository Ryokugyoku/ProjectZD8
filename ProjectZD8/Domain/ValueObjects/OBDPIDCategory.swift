/// リアルタイム表示で標準PIDを意味の近いまとまりへ分類します。
enum OBDPIDCategory: String, CaseIterable, Equatable, Hashable, Sendable {
    /// エンジンの負荷、回転、点火に関する項目です。
    case engine
    /// 温度に関する項目です。
    case temperature
    /// 燃料、吸気、排気、酸素センサーに関する項目です。
    case fuelAndAir
    /// 車速と運転者入力に関する項目です。
    case driving
    /// 稼働時間、走行距離、電源に関する項目です。
    case diagnostics

    /// 画面表示に使用するローカライズキーです。
    var nameKey: String {
        "telemetry.category.\(rawValue)"
    }

    /// 分類一覧で代表値として優先するPID要求です。
    var representativeRequest: OBDPIDRequest {
        switch self {
        case .engine: OBDPIDRequest(service: 0x01, pid: 0x0C)
        case .temperature: OBDPIDRequest(service: 0x01, pid: 0x05)
        case .fuelAndAir: OBDPIDRequest(service: 0x01, pid: 0x10)
        case .driving: OBDPIDRequest(service: 0x01, pid: 0x0D)
        case .diagnostics: OBDPIDRequest(service: 0x01, pid: 0x42)
        }
    }

    /// Service/PIDを表示分類へ割り当てます。
    ///
    /// 責務: 1件の標準PID要求をリアルタイム表示用の単一分類へ変換します。
    /// - Parameter request: 分類するService/PID要求。
    /// - Returns: 要求に対応する表示分類。
    static func category(for request: OBDPIDRequest) -> OBDPIDCategory {
        switch request.pid {
        case 0x04, 0x0C, 0x0E, 0x43:
            .engine
        case 0x05, 0x0F, 0x3C...0x3F, 0x46:
            .temperature
        case 0x06...0x0B, 0x10, 0x14...0x1B, 0x22, 0x23, 0x2C...0x2F, 0x32, 0x33, 0x44:
            .fuelAndAir
        case 0x0D, 0x11, 0x45, 0x47...0x4C:
            .driving
        default:
            .diagnostics
        }
    }
}
