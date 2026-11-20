import Foundation

/// Raw ログの1件から車速(OBD service 0x01・PID 0x0D)を取り出します。
///
/// PID 0x0D の応答は1バイトで、その値がそのまま km/h です(0〜255)。
nonisolated struct VehicleSpeedSampleExtractor: Sendable {
    /// 現在値を要求する OBD の service 番号。
    static let service: UInt8 = 0x01
    /// 車速の PID 番号。
    static let pid: UInt8 = 0x0D

    /// 取り出しの規則を作ります。
    ///
    /// 責務: 状態を持たない規則を用意します。
    init() {}

    /// Raw ログの1件が車速なら、その観測値を返します。
    ///
    /// 責務: service と PID が車速であることを確かめ、応答の先頭バイトを km/h として時刻と組にします。
    /// - Parameter entry: Raw ログの1件。
    /// - Returns: 車速でない、または応答が空なら `nil`。
    func observation(from entry: ConnectionSessionRawLogEntry) -> VehicleSpeedRawObservation? {
        guard entry.service == Self.service, entry.pid == Self.pid, let speedByte = entry.payload.first else { return nil }
        return VehicleSpeedRawObservation(
            observedAt: entry.observedAt,
            monotonicNanoseconds: entry.monotonicNanoseconds,
            kph: Double(speedByte)
        )
    }
}
