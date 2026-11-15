import Foundation
@testable import ProjectZD8

/// 対応ビットマップ、標準PID値、車種専用PID応答を固定で返し、全呼び出しを記録するアダプター境界のフェイクです。
///
/// 照会(`read` と `readVehicleSpecific`)は合計 `maximumQueryCount` 回までです。超えると
/// `AdapterPIDDiscoveryTestError.queryLimitExceeded` を投げ、照会が止まらない不具合をテストの停止ではなく失敗にします。
final class AdapterPIDTelemetryFake: OBDPIDTelemetryPort, @unchecked Sendable {
    /// 1つの fake が受け付ける照会の合計回数の上限です(標準範囲は最大8回。複数回の探索にも足りる値)。
    static let maximumQueryCount = 64
    /// 記録への並行アクセスを直列化します。
    private let lock = NSLock()
    /// 範囲先頭PID(00, 20, …)ごとの4バイト対応ビットマップです。
    private let bitmaps: [UInt8: [UInt8]]
    /// 標準データPIDへ返す応答バイトです。
    private let dataPayload: [UInt8]
    /// 車種専用PIDへ返す応答です。
    private let vehicleSpecificResponses: [OBDPIDRequest: [UInt8]]
    /// 対応ビットマップ照会で投げるエラーです。`nil` の場合は投げません。
    private let bitmapFailure: (any Error)?
    /// 車種専用PID照会で投げるエラーです。`nil` の場合は投げません。
    private let vehicleSpecificFailure: (any Error)?
    /// 照会された範囲先頭PIDの記録です。
    private var bitmapQueryLog: [UInt8] = []
    /// 車種専用PID照会ごとの要求一覧の記録です。
    private var vehicleSpecificLog: [[OBDPIDRequest]] = []
    /// 標準データPID読取ごとの要求一覧の記録です。
    private var dataReadLog: [[OBDPIDRequest]] = []
    /// これまでに受けた照会の合計回数です。
    private var queryCount = 0

    /// 固定応答と失敗を指定して生成します。
    ///
    /// 責務: 1件のテストで使うアダプター応答の組を固定します。
    /// - Parameters:
    ///   - bitmaps: 範囲先頭PIDごとの対応ビットマップ。
    ///   - dataPayload: 標準データPIDへ返す応答バイト。
    ///   - vehicleSpecificResponses: 車種専用PIDへ返す応答。
    ///   - bitmapFailure: 対応ビットマップ照会で投げるエラー。
    ///   - vehicleSpecificFailure: 車種専用PID照会で投げるエラー。
    init(
        bitmaps: [UInt8: [UInt8]] = [:],
        dataPayload: [UInt8] = [0x2A],
        vehicleSpecificResponses: [OBDPIDRequest: [UInt8]] = [:],
        bitmapFailure: (any Error)? = nil,
        vehicleSpecificFailure: (any Error)? = nil
    ) {
        self.bitmaps = bitmaps
        self.dataPayload = dataPayload
        self.vehicleSpecificResponses = vehicleSpecificResponses
        self.bitmapFailure = bitmapFailure
        self.vehicleSpecificFailure = vehicleSpecificFailure
    }

    /// 照会された範囲先頭PIDの一覧です。
    var bitmapQueries: [UInt8] { locked { bitmapQueryLog } }
    /// 範囲先頭PID 00 の照会回数です。探索の開始回数に等しくなります。
    var discoveryCount: Int { locked { bitmapQueryLog.filter { $0 == 0x00 }.count } }
    /// 車種専用PID照会ごとの要求一覧です。
    var vehicleSpecificQueries: [[OBDPIDRequest]] { locked { vehicleSpecificLog } }
    /// 標準データPID読取ごとの要求一覧です。
    var dataReads: [[OBDPIDRequest]] { locked { dataReadLog } }

    /// 範囲照会には対応ビットマップを、データPIDには固定値を返します。
    ///
    /// 責務: 要求を範囲照会とデータ読取に分けて記録し、固定応答へ変換します。
    /// - Parameters:
    ///   - requests: 読み取るService/PID要求。
    ///   - endpoint: 使用しないOBD終端。
    /// - Returns: 応答を用意した要求だけの辞書。
    /// - Throws: 照会回数の上限超過、または範囲照会で `bitmapFailure` を指定した場合はそのエラー。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] {
        try countQuery()
        let ranges = requests.filter { $0.service == 0x01 && $0.pid % 0x20 == 0 }
        let data = requests.filter { !($0.service == 0x01 && $0.pid % 0x20 == 0) }
        locked {
            bitmapQueryLog.append(contentsOf: ranges.map(\.pid))
            if !data.isEmpty { dataReadLog.append(data) }
        }
        if !ranges.isEmpty, let bitmapFailure { throw bitmapFailure }
        var responses: [OBDPIDRequest: [UInt8]] = [:]
        for range in ranges { responses[range] = bitmaps[range.pid] }
        for request in data { responses[request] = dataPayload }
        return responses
    }

    /// 車種専用PID要求を記録し、用意した応答だけを返します。
    ///
    /// 責務: 車種専用PID照会を記録して固定応答へ変換します。
    /// - Parameters:
    ///   - definitions: 照会する車種専用PID定義。
    ///   - endpoint: 使用しないOBD終端。
    /// - Returns: 要求のうち応答を用意したものだけの辞書。
    /// - Throws: 照会回数の上限超過、または `vehicleSpecificFailure` を指定した場合はそのエラー。
    func readVehicleSpecific(
        _ definitions: [OBDPIDDefinition],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        try countQuery()
        let requests = definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }
        locked { vehicleSpecificLog.append(requests) }
        if let vehicleSpecificFailure { throw vehicleSpecificFailure }
        return vehicleSpecificResponses.filter { requests.contains($0.key) }
    }

    /// 照会を1回数え、上限を超えたら失敗させます。
    ///
    /// 責務: 照会の合計回数を `maximumQueryCount` までに制限します。
    /// - Throws: 上限を超えた場合は `AdapterPIDDiscoveryTestError.queryLimitExceeded`。
    private func countQuery() throws {
        let exceeded = locked { () -> Bool in
            queryCount += 1
            return queryCount > Self.maximumQueryCount
        }
        if exceeded { throw AdapterPIDDiscoveryTestError.queryLimitExceeded }
    }

    /// ロック下で処理を実行します。
    ///
    /// 責務: 記録の読み書きを1つの臨界区間へまとめます。
    /// - Parameter body: 実行する処理。
    /// - Returns: 処理の戻り値。
    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
