import Foundation
@testable import ProjectZD8

/// 対応PID探索と取得対象決定のテストが共有する固定値です。
///
/// カタログは標準PID 05/0C/0D(数値化可能)、0F(数式なし)、ZD8専用 21/02・21/17、別型式 XX9 専用 22/01 を持ちます。
/// 既定のアダプターは標準PID 05/0C/0F/11 を対応と答えます(11 はカタログに無い)。
enum AdapterPIDDiscoveryFixtures {
    /// テスト用OBD終端です。
    static let endpoint = OBDConnectionEndpoint(transport: .serial, systemIdentifier: "/dev/unit2", displayName: "Unit2")
    /// テスト用登録車両IDです。
    static let vehicleID = VehicleID(rawValue: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!)
    /// ZD8専用の走行距離PIDです。
    static let zd8Odometer = OBDPIDRequest(service: 0x21, pid: 0x02)
    /// ZD8専用のAT油温PIDです。
    static let zd8OilTemperature = OBDPIDRequest(service: 0x21, pid: 0x17)
    /// 別型式XX9専用のPIDです。
    static let otherModelPID = OBDPIDRequest(service: 0x22, pid: 0x01)

    /// 標準Service 01のPID要求を返します。
    ///
    /// 責務: PID番号をService 01の要求へ変換します。
    /// - Parameter pid: Service 01内のPID番号。
    /// - Returns: Service 01の要求。
    static func standard(_ pid: UInt8) -> OBDPIDRequest { OBDPIDRequest(service: 0x01, pid: pid) }

    /// 標準Service 01の定義を返します。
    ///
    /// 責務: PID番号を1バイト数式付き、または数式なしの標準定義へ変換します。
    /// - Parameters:
    ///   - pid: Service 01内のPID番号。
    ///   - decodable: `false` の場合は数式を持たない定義にします。
    /// - Returns: 標準PID定義。
    static func standardDefinition(_ pid: UInt8, decodable: Bool = true) -> OBDPIDDefinition {
        OBDPIDDefinition(
            service: 0x01,
            pid: pid,
            nameKey: "test.unit2.\(pid)",
            requiredByteCount: decodable ? 1 : nil,
            formula: decodable ? "A" : nil,
            unit: "unit",
            minimumValue: 0,
            maximumValue: 255,
            sourceURI: "test://unit2",
            revision: 1
        )
    }

    /// 別型式XX9専用の定義です。
    static var otherModelDefinition: OBDPIDDefinition {
        OBDPIDDefinition(
            service: 0x22,
            pid: 0x01,
            header: 0x7E0,
            vehicleModelCode: "XX9",
            nameKey: "test.unit2.xx9",
            requiredByteCount: 1,
            formula: "A",
            unit: "unit",
            minimumValue: 0,
            maximumValue: 255,
            sourceURI: "test://unit2",
            revision: 1
        )
    }

    /// テスト用PIDカタログの全定義です。
    static var catalogDefinitions: [OBDPIDDefinition] {
        [standardDefinition(0x05), standardDefinition(0x0C), standardDefinition(0x0D), standardDefinition(0x0F, decodable: false)]
            + ZD8OBDPIDSeed.definitions + [otherModelDefinition]
    }

    /// テスト用PIDカタログです。
    static var catalog: FixedPIDDefinitionCatalog { FixedPIDDefinitionCatalog(definitions: catalogDefinitions) }

    /// 指定PIDを対応とする4バイト対応ビットマップを返します。
    ///
    /// 責務: 範囲先頭からのオフセットをbig-endianのビット位置へ変換します。
    /// - Parameters:
    ///   - pids: 対応とするPID。`base + 1` から `base + 32` の範囲。
    ///   - base: 範囲先頭PID。
    ///   - continues: `true` の場合は次範囲の継続ビット(オフセット32)を立てます。
    /// - Returns: 4バイトの対応ビットマップ。
    static func bitmap(_ pids: [UInt8], base: UInt8 = 0x00, continues: Bool = false) -> [UInt8] {
        var bytes: [UInt8] = [0, 0, 0, 0]
        let offsets = pids.map { Int($0) - Int(base) } + (continues ? [32] : [])
        for offset in offsets where (1...32).contains(offset) {
            bytes[(offset - 1) / 8] |= 0x80 >> UInt8((offset - 1) % 8)
        }
        return bytes
    }

    /// 標準PID 05/0C/0F/11 を対応と答え、ZD8走行距離だけに応答するアダプターです。
    ///
    /// 責務: 既定の対応状況を持つアダプターのフェイクを生成します。
    /// - Parameter bitmapFailure: 対応ビットマップ照会で投げるエラー。
    /// - Returns: 既定応答のアダプターフェイク。
    static func adapter(bitmapFailure: (any Error)? = nil) -> AdapterPIDTelemetryFake {
        AdapterPIDTelemetryFake(
            bitmaps: [0x00: bitmap([0x05, 0x0C, 0x0F, 0x11])],
            vehicleSpecificResponses: [zd8Odometer: [0, 0, 0, 10]],
            bitmapFailure: bitmapFailure
        )
    }

    /// 対応PIDを1件も答えないアダプターです。
    static var silentAdapter: AdapterPIDTelemetryFake {
        AdapterPIDTelemetryFake(bitmaps: [0x00: bitmap([])])
    }

    /// 指定車両の収集有効な保存済み対応PIDを返します。
    ///
    /// 責務: Service/PIDと収集選択の組を保存済み対応PIDへ変換します。
    /// - Parameter entries: Service/PIDと収集選択の組。
    /// - Returns: 固定確認日時の保存済み対応PID。
    static func storedCapabilities(_ entries: [(OBDPIDRequest, Bool)]) -> [VehiclePIDCapability] {
        entries.map {
            VehiclePIDCapability(vehicleID: vehicleID, request: $0.0, isCollectionEnabled: $0.1, discoveredAt: .distantPast)
        }
    }
}

