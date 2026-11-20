/// ホーム画面の配置です。
///
/// iOSとmacOSで共通の判定結果です。
nonisolated enum HomeScreenLayout: Equatable, Sendable {
    /// 未接続の配置です。アダプターカードと接続導線を出します。
    case adapterSetup
    /// 接続中の配置です。セッション見出しとリアルタイム表示を出します。
    case connectedSession
}
