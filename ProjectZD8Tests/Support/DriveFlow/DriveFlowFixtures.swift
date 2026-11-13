import Foundation
@testable import ProjectZD8

/// 取得フローのテストで共通に使う部品です。
enum DriveFlowFixtures {
    static let rpm = OBDPIDRequest(service: 0x01, pid: 0x0C)
    static let speed = OBDPIDRequest(service: 0x01, pid: 0x0D)
    static let load = OBDPIDRequest(service: 0x01, pid: 0x04)
    static let throttle = OBDPIDRequest(service: 0x01, pid: 0x11)
    static let coolant = OBDPIDRequest(service: 0x01, pid: 0x05)
    static let odometer = OBDPIDRequest(service: 0x01, pid: 0xA6)
    static let sinceCleared = OBDPIDRequest(service: 0x01, pid: 0x31)
    static let zd8Odometer = OBDPIDRequest(service: 0x21, pid: 0x02)

    static let fastRequests: Set<OBDPIDRequest> = [load, rpm, speed, throttle]
    static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    static func identification(vin: String? = "WVWZZZ1JZXW000001") -> VehicleIdentification {
        VehicleIdentification(vin: vin, adapterDescription: "ELM327 v1.5", protocolDescription: "ISO 15765-4", observedAt: epoch)
    }

    static func adapter(transport: AdapterTransport = .bluetoothLowEnergy) -> AdapterDescriptor {
        AdapterDescriptor(transport: transport, systemIdentifier: "ABC", displayName: "OBDLink CX")
    }

    static func session(vehicleID: VehicleID = VehicleID()) -> DriveSession {
        DriveSession(
            vehicleID: vehicleID, startedAt: epoch, isDemo: false, adapterName: "OBDLink CX",
            adapterTransport: .bluetoothLowEnergy, platform: .mac, deviceID: "device", deviceName: "Mac",
            appVersion: "1.0", appBuild: "1", pollingPolicyVersion: AcquisitionPollingPolicy.version, modifiedAt: epoch
        )
    }

    /// 要求を名前順に1件ずつ構築した、単純な1バイト式のセッションPIDです。
    static func pid(
        _ ordinal: Int, _ request: OBDPIDRequest, fast: Bool = false, enabled: Bool = true, header: UInt16? = nil,
        formula: String? = "A", bytes: Int? = 1, minimum: Double? = 0, maximum: Double? = 255
    ) -> SessionPID {
        SessionPID(
            ordinal: ordinal, request: request, header: header, support: .supported, isCollectionEnabled: enabled,
            isFastGroup: fast, definitionRevision: 1, requiredByteCount: bytes, formula: formula, unit: "u",
            minimumValue: minimum, maximumValue: maximum
        )
    }

    static func vehicle(vin: String = "WVWZZZ1JZXW000001", name: String = "My ZD8") -> Vehicle {
        Vehicle(vin: vin, name: name, createdAt: epoch, modifiedAt: epoch)
    }

    /// 条件が成り立つまで待ちます。
    @MainActor
    static func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}
