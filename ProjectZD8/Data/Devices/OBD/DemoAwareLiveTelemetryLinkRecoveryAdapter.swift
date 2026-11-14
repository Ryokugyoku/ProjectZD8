/// デモ終端と実終端を対応する回復操作へ振り分けます。
///
/// デモ終端は物理通信を持たず途絶しないため、回復操作は何もせず成功します。
struct DemoAwareLiveTelemetryLinkRecoveryAdapter: LiveTelemetryLinkRecoveryPort {
    /// 実OBD通信の回復操作を行う境界です。
    private let live: any LiveTelemetryLinkRecoveryPort

    /// 実通信の回復操作境界を保持して生成します。
    ///
    /// 責務: 実終端の回復操作を注入します。
    /// - Parameter live: 実終端の回復操作を行う境界。
    init(live: any LiveTelemetryLinkRecoveryPort) {
        self.live = live
    }

    /// 実終端だけプロンプト再同期を行います。
    ///
    /// 責務: デモ終端では何もせず、実終端では注入先へ委譲します。
    /// - Parameter endpoint: 取得に使っているOBD終端。
    /// - Throws: 実終端で注入先が送出したエラー。
    func promptResync(using endpoint: OBDConnectionEndpoint) async throws {
        guard !DemoOBDAdapter.matches(endpoint) else { return }
        try await live.promptResync(using: endpoint)
    }

    /// 実終端だけ `ATZ` からの再初期化を行います。
    ///
    /// 責務: デモ終端では何もせず、実終端では注入先へ委譲します。
    /// - Parameter endpoint: 取得に使っているOBD終端。
    /// - Throws: 実終端で注入先が送出したエラー。
    func reinitializeFromReset(using endpoint: OBDConnectionEndpoint) async throws {
        guard !DemoOBDAdapter.matches(endpoint) else { return }
        try await live.reinitializeFromReset(using: endpoint)
    }

    /// 実終端だけ切断と再接続を行います。
    ///
    /// 責務: デモ終端では何もせず、実終端では注入先へ委譲します。
    /// - Parameter endpoint: 取得に使っているOBD終端。
    /// - Throws: 実終端で注入先が送出したエラー。
    func reconnectLink(using endpoint: OBDConnectionEndpoint) async throws {
        guard !DemoOBDAdapter.matches(endpoint) else { return }
        try await live.reconnectLink(using: endpoint)
    }
}
