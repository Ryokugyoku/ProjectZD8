#if os(iOS)
import Foundation

/// iOSプロセスに1本だけ存在する常駐BLEリンクと、その受信を引き受ける唯一のバイトストリームです。
///
/// 監視・車両識別・テレメトリは、すべてこの値が保持するストリームとトランスポート選択を共有します。
@MainActor
struct IOSResidentAdapterLink {
    /// 登録済みアダプターへ保留接続を出し続ける常駐リンクです。
    let link: BLEAdapterLink

    /// 常駐リンクの受信を占有し、排他リースで分配するバイトストリームです(リンク1本につき1個)。
    let stream: AdapterLinkByteStream

    /// BLE終端への接続で常駐リンク上のトランスポートを使うかどうかを選ぶ型です。
    let transportSelector: AdapterLinkOBDTransportSelector

    /// 状態復元に対応する中央役で常駐リンクを1本だけ生成します。
    ///
    /// 責務: 中央役・リンク・バイトストリーム・トランスポート選択を1組だけ組み立てます。起動時に1回だけ呼びます。
    /// - Returns: 未開始(`idle`)の常駐リンク一式。開始は常駐リンク監視が行います。
    static func make() -> IOSResidentAdapterLink {
        let link = BLEAdapterLink(central: AppleCoreBluetoothCentralRole())
        let stream = AdapterLinkByteStream(link: link)
        let transportSelector = AdapterLinkOBDTransportSelector(
            stream: stream,
            linkTargetIdentifier: { [weak link] in link?.targetIdentifier }
        )
        return IOSResidentAdapterLink(link: link, stream: stream, transportSelector: transportSelector)
    }
}
#endif
