import Foundation
@testable import ProjectZD8

/// LiveTelemetry のテストが共有するPID定義・終端・車両IDの値を生成します。
enum LiveTelemetryTestDefinitions {
    /// テスト用OBD接続終端です。
    static let endpoint = OBDConnectionEndpoint(transport: .serial, systemIdentifier: "/dev/cu.test", displayName: "Test adapter")

    /// テスト用の車両IDです。
    static let vehicleID = VehicleID(rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!)

    /// 1バイトをそのまま値にする Service 01 の定義を生成します。
    ///
    /// 責務: PID番号と範囲だけを差し替えた、数値化可能な標準PID定義を返します。
    /// - Parameters:
    ///   - pid: Service 01 内のPID番号。
    ///   - maximumValue: 有効範囲の上限。下限は0です。
    /// - Returns: 式 `A`、必要バイト数1の定義。
    static func standard(_ pid: UInt8, maximumValue: Double = 255) -> OBDPIDDefinition {
        OBDPIDDefinition(
            service: 0x01,
            pid: pid,
            nameKey: "test.pid.\(pid)",
            requiredByteCount: 1,
            formula: "A",
            unit: "unit",
            minimumValue: 0,
            maximumValue: maximumValue,
            sourceURI: "test://pid",
            revision: 1
        )
    }

    /// 指定PID番号の Service 01 定義を並べて返します。
    ///
    /// 責務: 複数の標準PID定義を入力順に生成します。
    /// - Parameter pids: Service 01 内のPID番号。
    /// - Returns: 入力順の定義。
    static func standard(_ pids: [UInt8]) -> [OBDPIDDefinition] {
        pids.map { standard($0) }
    }

    /// 定義から要求を取り出します。
    ///
    /// 責務: 定義のService/PIDを要求へ変換します。
    /// - Parameter definition: PID定義。
    /// - Returns: 同じService/PIDの要求。
    static func request(_ definition: OBDPIDDefinition) -> OBDPIDRequest {
        OBDPIDRequest(service: definition.service, pid: definition.pid)
    }

    /// Service 01 の要求を生成します。
    ///
    /// 責務: PID番号を Service 01 の要求へ変換します。
    /// - Parameter pid: Service 01 内のPID番号。
    /// - Returns: 要求。
    static func request(_ pid: UInt8) -> OBDPIDRequest {
        OBDPIDRequest(service: 0x01, pid: pid)
    }

    /// 定義ごとに収集有効の対応済みcapabilityを生成します。
    ///
    /// 責務: 取得記録の開始入力に渡す、定義と同数のcapabilityを返します。
    /// - Parameter definitions: 取得対象の定義。
    /// - Returns: 定義順のcapability。
    static func capabilities(for definitions: [OBDPIDDefinition]) -> [ConnectionSessionAcquisitionPIDCapabilityInput] {
        definitions.map {
            ConnectionSessionAcquisitionPIDCapabilityInput(request: request($0), support: .supported, isCollectionEnabled: true)
        }
    }
}
