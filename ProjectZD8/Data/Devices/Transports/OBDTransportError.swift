/// バイトストリームTransportが投げる通信失敗です。`ELM327OBDLink` が `OBDLinkError` へ写像します。
nonisolated enum OBDTransportError: Error, Equatable, Sendable {
    /// このTransportでは扱えないアダプターまたはBluetooth構成だった。
    case transportUnsupported
    /// 接続できない、書込めない、または通信が切れた。
    case connectionFailed
    /// 期限内に開通または応答しなかった。
    case timedOut
}
