import Foundation

/// 接続終端ごとに、常駐リンク上のトランスポートか従来のトランスポートかを選んで生成します。
///
/// Composition の `makeTransport` から呼ぶための小さな型です。判定は `AdapterLinkTransportSelectionPolicy` に任せます。
@MainActor
final class AdapterLinkOBDTransportSelector {
    /// 常駐リンクの受信を引き受けるバイトストリームです。
    private let stream: AdapterLinkByteStream
    /// 常駐リンクの接続対象のPeripheral UUIDを返す処理です。
    private let linkTargetIdentifier: @MainActor () -> UUID?
    /// 選択の判定方針です。
    private let policy = AdapterLinkTransportSelectionPolicy()

    /// バイトストリームと接続対象の取得方法を固定して生成します。
    ///
    /// 責務: 選択に必要な常駐リンクの情報源を結び付けます。
    /// - Parameters:
    ///   - stream: 常駐リンクの受信を引き受けるバイトストリーム。
    ///   - linkTargetIdentifier: 常駐リンクの接続対象を返す処理(例: `{ [weak link] in link?.targetIdentifier }`)。
    init(stream: AdapterLinkByteStream, linkTargetIdentifier: @escaping @MainActor () -> UUID?) {
        self.stream = stream
        self.linkTargetIdentifier = linkTargetIdentifier
    }

    /// 終端に合うトランスポートを返します。
    ///
    /// 責務: 常駐リンクが同じアダプターを `ready` で保持していれば常駐リンク上のトランスポートを、そうでなければ従来のものを返します。
    /// - Parameters:
    ///   - endpoint: 接続しようとしている終端。
    ///   - fallback: 常駐リンクを使わない場合の従来のトランスポート生成処理。
    /// - Returns: 選んだトランスポート。
    /// - Throws: 従来のトランスポート生成が投げたエラー。
    func transport(
        for endpoint: OBDConnectionEndpoint,
        fallback: (OBDConnectionEndpoint) throws -> any OBDCommandTransport
    ) rethrows -> any OBDCommandTransport {
        let usesResidentLink = policy.usesResidentLink(
            for: endpoint,
            linkTargetIdentifier: linkTargetIdentifier(),
            linkState: stream.linkState
        )
        guard usesResidentLink else { return try fallback(endpoint) }
        return AdapterLinkOBDCommandTransport(stream: stream)
    }
}
