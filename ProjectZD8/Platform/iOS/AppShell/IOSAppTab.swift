#if os(iOS)
/// iOS のタブ(ドライブ・ログ・ガレージ・設定)です。
enum IOSAppTab: Hashable {
    case drive
    case logs
    case garage
    case settings
}
#endif
