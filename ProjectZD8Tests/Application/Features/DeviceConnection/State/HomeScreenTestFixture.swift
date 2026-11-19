import Foundation
@testable import ProjectZD8

/// ホーム画面の純粋型テストで使う接続先・表示状態・セッション・車両を作ります。
@MainActor
enum HomeScreenTestFixture {
    /// 記録の開始時刻に使う固定時刻です。
    static let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    /// アダプターの接続先です。
    static let endpoint = OBDConnectionEndpoint(transport: .bluetoothLowEnergy, systemIdentifier: "adapter-1", displayName: "OBD BLE")
    /// アダプターと別の接続先です(OS ごとの接続先規則で選ばれた値の代わり)。
    static let otherEndpoint = OBDConnectionEndpoint(transport: .serial, systemIdentifier: "adapter-2", displayName: "OBD USB")

    /// 表示状態を作ります。
    ///
    /// 責務: フェーズと車両の文脈を指定した表示状態を返します。
    /// - Parameters:
    ///   - phase: フェーズ。
    ///   - vehicle: 車両の文脈。
    /// - Returns: 作った表示状態。
    static func telemetry(phase: LiveTelemetryState.Phase, vehicle: LiveTelemetryVehicleContext? = nil) -> LiveTelemetryState {
        var state = LiveTelemetryState()
        state.phase = phase
        state.vehicle = vehicle
        return state
    }

    /// 接続セッションを作ります。
    ///
    /// 責務: 車両名と終了の有無を指定したセッションを返します。
    /// - Parameters:
    ///   - vehicleName: セッションに記録された車両名。nil なら車両なし。
    ///   - vehicleID: セッションの車両 ID。
    ///   - endedAt: 終了時刻。nil なら進行中。
    /// - Returns: 作ったセッション。
    static func session(vehicleName: String? = nil, vehicleID: VehicleID = VehicleID(), endedAt: Date? = nil) -> ConnectionSession {
        var session = ConnectionSession(
            accountIdentifier: "test-account",
            startedAt: startedAt,
            vehicle: vehicleName.map { ConnectionSessionVehicle(id: vehicleID, name: $0, displayIdentifier: "test") }
        )
        session.endedAt = endedAt
        return session
    }

    /// 車両プロフィールを作ります。
    ///
    /// 責務: ID と名前を指定した車両を返します。
    /// - Parameters:
    ///   - id: 車両 ID。
    ///   - name: 車両名。
    /// - Returns: 作った車両。
    static func vehicle(id: VehicleID, name: String) -> VehicleProfile {
        VehicleProfile(id: id, vin: "TESTVIN0000000001", name: name, updatedAt: startedAt)
    }
}
