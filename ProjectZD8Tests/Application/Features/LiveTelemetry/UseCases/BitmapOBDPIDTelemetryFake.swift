import Foundation
@testable import ProjectZD8

/// 対応PIDビットマップ(PID 00/20/40…)の問い合わせへ、予約したビットマップを返す取得境界のフェイクです。
@MainActor
final class BitmapOBDPIDTelemetryFake: OBDPIDTelemetryPort {
    /// ビットマップ用PIDごとの応答です。無いPIDは応答なしです。
    private let bitmaps: [UInt8: [UInt8]]
    /// 送出する失敗です。`nil` なら失敗しません。
    private let failure: (any Error)?
    /// 問い合わせたビットマップ用PIDです。問い合わせ順に並びます。
    private(set) var queriedPIDs: [UInt8] = []
    /// 車種専用PIDの問い合わせ回数です。
    private(set) var vehicleSpecificCallCount = 0

    /// ビットマップと失敗を予約して生成します。
    ///
    /// 責務: 問い合わせに返す応答を固定します。
    /// - Parameters:
    ///   - bitmaps: ビットマップ用PIDごとの応答。
    ///   - failure: 送出する失敗。
    init(bitmaps: [UInt8: [UInt8]], failure: (any Error)? = nil) {
        self.bitmaps = bitmaps
        self.failure = failure
    }

    /// 指定PIDの対応ビットを立てたビットマップを作ります。
    ///
    /// 責務: 基準PIDからの位置(1〜32)に対応するビットを、先頭バイトの最上位ビットから立てます。
    /// - Parameters:
    ///   - pids: 対応を示すPID。基準PIDより後ろで32以内のものだけ使います。
    ///   - base: ビットマップ用PID(0x00, 0x20, …)。
    ///   - continues: 次のビットマップへ続く(位置32)を立てるかどうか。
    /// - Returns: 4バイトのビットマップ。
    static func bitmap(supporting pids: [UInt8], base: UInt8, continues: Bool) -> [UInt8] {
        var bytes: [UInt8] = [0, 0, 0, 0]
        let offsets = pids.map { Int($0) - Int(base) }.filter { (1...31).contains($0) } + (continues ? [32] : [])
        for offset in offsets {
            bytes[(offset - 1) / 8] |= 0x80 >> UInt8((offset - 1) % 8)
        }
        return bytes
    }

    /// 問い合わせへ予約したビットマップを返します。
    ///
    /// 責務: 問い合わせを記録し、予約した失敗を送出するか、応答のあるPIDだけを返します。
    /// - Parameters:
    ///   - requests: 問い合わせ。
    ///   - endpoint: 使用するOBD終端。
    /// - Returns: 予約した応答。
    /// - Throws: 予約した失敗。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] {
        queriedPIDs += requests.map(\.pid)
        if let failure { throw failure }
        return Dictionary(uniqueKeysWithValues: requests.compactMap { request in bitmaps[request.pid].map { (request, $0) } })
    }

    /// 車種専用PIDの問い合わせを記録します。
    ///
    /// 責務: 呼ばれたことを数え、応答なしを返します。
    /// - Parameters:
    ///   - definitions: 車種専用定義。
    ///   - endpoint: 使用するOBD終端。
    /// - Returns: 空の応答。
    func readVehicleSpecific(_ definitions: [OBDPIDDefinition], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] {
        vehicleSpecificCallCount += 1
        return [:]
    }
}
