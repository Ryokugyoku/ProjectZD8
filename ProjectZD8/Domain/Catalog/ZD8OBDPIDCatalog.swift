import Foundation

/// ユーザー確認済みのZD8専用読取りPID定義を提供します。
nonisolated enum ZD8OBDPIDCatalog {
    /// 重複なく識別できる走行距離とAT油温の定義です。
    static let definitions: [OBDPIDDefinition] = [
        OBDPIDDefinition(
            service: 0x21,
            pid: 0x02,
            header: 0x7E0,
            vehicleModelCode: ZD8VehicleModelPolicy.modelCode,
            nameKey: "obd.pid.zd8.21.02.name",
            requiredByteCount: 4,
            formula: "(A * 16777216 + B * 65536 + C * 256 + D) / 10",
            unit: "km",
            minimumValue: 0,
            maximumValue: 429_496_729.5,
            sourceURI: "projectzd8://requirements/zd8-pids/2026-07-23",
            revision: 1,
            summaryKey: "obd.pid.zd8.21.02.summary",
            highValueKey: "obd.pid.help.unconfirmed.high",
            lowValueKey: "obd.pid.help.unconfirmed.low",
            correlationKey: "obd.pid.zd8.21.02.correlation"
        ),
        OBDPIDDefinition(
            service: 0x21,
            pid: 0x17,
            header: 0x7E1,
            vehicleModelCode: ZD8VehicleModelPolicy.modelCode,
            nameKey: "obd.pid.zd8.21.17.name",
            requiredByteCount: 1,
            formula: "A - 58",
            unit: "°C",
            minimumValue: -58,
            maximumValue: 197,
            sourceURI: "projectzd8://requirements/zd8-pids/2026-07-23",
            revision: 1,
            summaryKey: "obd.pid.zd8.21.17.summary",
            highValueKey: "obd.pid.zd8.21.17.high",
            lowValueKey: "obd.pid.zd8.21.17.low",
            correlationKey: "obd.pid.zd8.21.17.correlation"
        )
    ]
}
