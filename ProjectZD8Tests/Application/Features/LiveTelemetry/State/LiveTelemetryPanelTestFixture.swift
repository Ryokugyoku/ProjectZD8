import Foundation
@testable import ProjectZD8

/// リアルタイム表示パネルの純粋型テストで使う PID サンプルと表示状態を作ります。
@MainActor
enum LiveTelemetryPanelTestFixture {
    /// サンプルの観測時刻に使う固定時刻です。
    static let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    /// 再試行の条件に使う接続先です。
    static let endpoint = OBDConnectionEndpoint(transport: .serial, systemIdentifier: "/dev/cu.test", displayName: "Test Adapter")
    /// 再試行の条件に使う登録済み車両の文脈です。
    static let registeredVehicle = LiveTelemetryVehicleContext.registered(VehicleID(), vehicleModelCode: "ZD8")

    /// 1件の PID サンプルを作ります。
    ///
    /// 責務: 要求と値・単位・型式コードを指定したサンプルを、PID ごとに区別できる文言キー付きで返します。
    /// - Parameters:
    ///   - pid: PID 番号。
    ///   - service: サービス番号。既定は 01。
    ///   - value: 値。
    ///   - unit: 単位。
    ///   - modelCode: 車種専用 PID の型式コード。
    /// - Returns: 作ったサンプル。
    static func sample(
        pid: UInt8,
        service: UInt8 = 0x01,
        value: Double = 1,
        unit: String = "unit",
        modelCode: String? = nil
    ) -> OBDPIDSample {
        let suffix = String(format: "%02X.%02X", service, pid)
        return OBDPIDSample(
            request: OBDPIDRequest(service: service, pid: pid),
            nameKey: "test.pid.\(suffix).name",
            value: value,
            unit: unit,
            vehicleModelCode: modelCode,
            observedAt: observedAt,
            summaryKey: "test.pid.\(suffix).summary",
            highValueKey: "test.pid.\(suffix).high",
            lowValueKey: "test.pid.\(suffix).low",
            correlationKey: "test.pid.\(suffix).correlation"
        )
    }

    /// 表示状態を作ります。
    ///
    /// 責務: フェーズとサンプル・失敗キー・一時停止状態・接続先・車両・応答 PID 数を指定した状態を返します。
    /// - Returns: 作った表示状態。
    static func state(
        phase: LiveTelemetryState.Phase,
        samples: [OBDPIDSample] = [],
        failureKey: String? = nil,
        pauseStatus: LiveTelemetryPauseStatus? = nil,
        endpoint: OBDConnectionEndpoint? = nil,
        vehicle: LiveTelemetryVehicleContext? = nil,
        supportedPIDCount: Int = 0
    ) -> LiveTelemetryState {
        var state = LiveTelemetryState()
        state.phase = phase
        state.samples = samples
        state.failureKey = failureKey
        state.pauseStatus = pauseStatus
        state.endpoint = endpoint
        state.vehicle = vehicle
        state.supportedPIDCount = supportedPIDCount
        return state
    }
}
