import Foundation
@testable import ProjectZD8

/// 分析テストで使う車両・セッション・サンプルの作成補助です。
nonisolated enum AnalysisFixtures {
    static let rpm = OBDPIDRequest(service: 0x01, pid: 0x0C)
    static let speed = OBDPIDRequest(service: 0x01, pid: 0x0D)
    static let coolant = OBDPIDRequest(service: 0x01, pid: 0x05)

    /// 責務: テスト用の車両を作ります。
    static func vehicle(name: String = "Test Car") -> Vehicle {
        Vehicle(vin: "VIN123", name: name, manufacturer: "Maker", modelYear: 2020)
    }

    /// 責務: 取得時に固定する式を指定してセッションPIDを作ります。
    static func pid(_ request: OBDPIDRequest, ordinal: Int, bytes: Int, formula: String?, unit: String, min: Double?, max: Double?, fast: Bool = true, revision: Int = 1) -> SessionPID {
        SessionPID(ordinal: ordinal, request: request, header: nil, support: .supported, isCollectionEnabled: true, isFastGroup: fast, definitionRevision: revision, requiredByteCount: bytes, formula: formula, unit: unit, minimumValue: min, maximumValue: max)
    }

    /// 責務: 回転数・車速・水温の標準的なセッションPIDを作ります。
    static func standardPIDs() -> [SessionPID] {
        [
            pid(rpm, ordinal: 0, bytes: 2, formula: "(A * 256 + B) / 4", unit: "rpm", min: 0, max: 16_383.75),
            pid(speed, ordinal: 1, bytes: 1, formula: "A", unit: "km/h", min: 0, max: 255),
            pid(coolant, ordinal: 2, bytes: 1, formula: "A - 40", unit: "°C", min: -40, max: 215, fast: false)
        ]
    }

    /// 責務: 終了済みの走行セッションを作ります。
    static func session(vehicleID: VehicleID, startedAt: Date = Date(timeIntervalSince1970: 1_000_000), duration: TimeInterval = 100, isDemo: Bool = false, raw: RawAvailability = .local, sampleCount: Int = 0) -> DriveSession {
        DriveSession(
            vehicleID: vehicleID, startedAt: startedAt, endedAt: startedAt.addingTimeInterval(duration), endReason: .userStopped, isDemo: isDemo,
            adapterName: "Adapter", adapterTransport: .demo, platform: .mac, deviceID: "d", deviceName: "d", appVersion: "1", appBuild: "1",
            pollingPolicyVersion: 1, odometerStartKilometers: 1000, odometerEndKilometers: 1010, distanceSource: .odometer, sampleCount: sampleCount, respondedCount: sampleCount,
            rawAvailability: raw, modifiedAt: startedAt
        )
    }

    /// 責務: 応答サンプルを作ります。
    static func sample(_ sequence: Int64, seconds: Double, _ request: OBDPIDRequest, _ outcome: SampleOutcome = .responded, payload: [UInt8] = []) -> SessionSample {
        SessionSample(sequence: sequence, tick: Int(sequence), elapsedMicroseconds: Int64(seconds * 1_000_000), request: request, outcome: outcome, payload: Data(payload))
    }
}
