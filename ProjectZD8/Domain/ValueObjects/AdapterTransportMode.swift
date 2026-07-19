import Foundation

/// アダプター探索で利用する物理接続方式を表します。
enum AdapterTransportMode: String, CaseIterable, Identifiable, Sendable {
    /// USB接続されたデバイスを対象にします。
    case usb

    /// macOSから参照できるBluetoothデバイスを対象にします。
    case bluetooth

    /// 接続方式を一意に識別する安定識別子です。
    var id: String { rawValue }
}
