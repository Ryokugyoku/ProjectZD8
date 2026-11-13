#if os(iOS)
/// ガレージのナビゲーションスタックが積む行き先です。
enum IOSGarageRoute: Hashable {
    /// 車両の詳細です。
    case vehicle(VehicleID)
    /// 車両のPID収集設定です。
    case pidSettings(VehicleID)
    /// 車両の整備記録です。
    case maintenance(VehicleID)
}
#endif
