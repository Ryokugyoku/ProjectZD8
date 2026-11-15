/// 接続終端に対して、どのトランスポートを使うかの判定結果です。
nonisolated enum AdapterLinkTransportSelection: Equatable, Sendable {
    /// 常駐リンク上のトランスポートを使います。
    case residentLink
    /// 従来のトランスポート(自前の接続)を使います。
    case fallback
    /// 常駐リンクだけを使うべきなのに、常駐リンクが同じアダプターを `ready` で保持していません。接続を開きません。
    case residentLinkUnavailable
}
