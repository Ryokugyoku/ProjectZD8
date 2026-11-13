import Foundation

/// サービス01の対応PIDビットマップ(00/20/40/…)の解読です。
nonisolated struct ELM327SupportBitmap: Equatable, Sendable {
    /// このビットマップが対応と示したデータPID(範囲先頭の「対応PID」自身は含みません)。
    let supportedPIDs: [UInt8]
    /// 次の範囲(`base + 0x20`)のビットマップを要求できるかどうかです。
    let hasNextRange: Bool

    /// 4バイトのビットマップを解読します。
    ///
    /// 責務: 範囲先頭 `base` の4バイト応答を、対応PID一覧と次範囲の有無へ変換します。
    /// - Parameters:
    ///   - base: 範囲先頭のPID(0x00, 0x20, …)。
    ///   - payload: サービスとPIDのエコーを除いた応答。4バイト未満なら `nil`。
    init?(base: UInt8, payload: [UInt8]) {
        guard payload.count >= 4 else { return nil }
        var pids: [UInt8] = []
        for offset in 0..<32 {
            let byte = payload[offset / 8]
            guard byte & (0x80 >> UInt8(offset % 8)) != 0 else { continue }
            let pid = Int(base) + offset + 1
            guard pid <= 0xFF else { continue }
            pids.append(UInt8(pid))
        }
        let nextBase = Int(base) + 0x20
        hasNextRange = nextBase <= 0xE0 && pids.contains(UInt8(nextBase))
        supportedPIDs = pids.filter { $0 & 0x1F != 0 }
    }
}
