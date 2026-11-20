/// 走行ルートを色分けできる指標です。区分の境界は固定値で、セッションの間で色の意味が変わりません。
nonisolated enum RouteAnalysisColorMetric: String, CaseIterable, Sendable {
    /// 車速(0x01/0x0D、km/h)。
    case vehicleSpeed
    /// エンジン回転数(0x01/0x0C、rpm)。
    case engineSpeed
    /// エンジン負荷(0x01/0x04、%)。
    case engineLoad
    /// 冷却水温(0x01/0x05、°C)。
    case coolantTemperature

    /// 指標の値を記録する PID です。
    var pid: OBDPIDRequest {
        switch self {
        case .vehicleSpeed: OBDPIDRequest(service: 0x01, pid: 0x0D)
        case .engineSpeed: OBDPIDRequest(service: 0x01, pid: 0x0C)
        case .engineLoad: OBDPIDRequest(service: 0x01, pid: 0x04)
        case .coolantTemperature: OBDPIDRequest(service: 0x01, pid: 0x05)
        }
    }

    /// 指標の名前のローカライズキーです。
    var titleKey: String {
        switch self {
        case .vehicleSpeed: "analysis.route.metric.vehicle_speed"
        case .engineSpeed: "analysis.route.metric.engine_speed"
        case .engineLoad: "analysis.route.metric.engine_load"
        case .coolantTemperature: "analysis.route.metric.coolant_temperature"
        }
    }

    /// PID 定義に単位が無い時に使う単位です(ローカライズしません)。
    var fallbackUnit: String {
        switch self {
        case .vehicleSpeed: "km/h"
        case .engineSpeed: "rpm"
        case .engineLoad: "%"
        case .coolantTemperature: "°C"
        }
    }

    /// 指標の5区分の境界です。
    var bands: RouteAnalysisColorBands {
        guard let bands = RouteAnalysisColorBands(boundaries: boundaries) else {
            preconditionFailure("固定の境界は有限で狭義の昇順です")
        }
        return bands
    }

    /// 指標の固定の境界の値です。
    private var boundaries: [Double] {
        switch self {
        case .vehicleSpeed: [20, 40, 60, 80]
        case .engineSpeed: [1_500, 2_500, 3_500, 4_500]
        case .engineLoad: [20, 40, 60, 80]
        case .coolantTemperature: [60, 80, 95, 105]
        }
    }
}
