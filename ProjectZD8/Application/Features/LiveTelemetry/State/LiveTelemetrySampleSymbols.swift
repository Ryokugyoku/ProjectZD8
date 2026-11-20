/// リアルタイム表示のPIDと分類に対応するSF Symbol名を返す名前空間です。
///
/// iOSとmacOSで共通の対応表です。
enum LiveTelemetrySampleSymbols {
    /// 回転数(Service 01 / PID 0C)の要求です。
    private static let engineSpeedRequest = OBDPIDRequest(service: 0x01, pid: 0x0C)
    /// 車速(Service 01 / PID 0D)の要求です。
    private static let vehicleSpeedRequest = OBDPIDRequest(service: 0x01, pid: 0x0D)

    /// 主要値カードのシンボルを返します。
    ///
    /// 責務: 1件のPID要求を回転数・車速・その他を区別するSF Symbol名へ変換します。
    /// - Parameter request: シンボルを選ぶPID要求。
    /// - Returns: 回転数なら `gauge.with.dots.needle.67percent`、車速なら `road.lanes`、それ以外は `waveform.path.ecg`。
    static func primarySymbol(for request: OBDPIDRequest) -> String {
        if request == engineSpeedRequest { return "gauge.with.dots.needle.67percent" }
        if request == vehicleSpeedRequest { return "road.lanes" }
        return "waveform.path.ecg"
    }

    /// 分類のシンボルを返します。
    ///
    /// 責務: 1件のPID分類を分類カード・分類選択用のSF Symbol名へ変換します。
    /// - Parameter category: シンボルを選ぶPID分類。
    /// - Returns: 分類の意味を補助するSF Symbol名。
    static func categorySymbol(for category: OBDPIDCategory) -> String {
        switch category {
        case .engine: "engine.combustion"
        case .temperature: "thermometer.medium"
        case .fuelAndAir: "wind"
        case .driving: "steeringwheel"
        case .diagnostics: "stethoscope"
        }
    }
}
