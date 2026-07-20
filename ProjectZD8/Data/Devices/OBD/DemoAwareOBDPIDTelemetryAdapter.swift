/// デモ終端と実終端を対応するPID取得境界へ振り分けます。
struct DemoAwareOBDPIDTelemetryAdapter: OBDPIDTelemetryPort {
    /// 実OBD通信を行うPID取得境界です。
    private let live: any OBDPIDTelemetryPort
    /// 物理通信なしで応答を返すPID取得境界です。
    private let demo: any OBDPIDTelemetryPort

    /// 実通信境界とデモ境界を保持して生成します。
    ///
    /// 責務: 2種類のPID取得境界を終端識別子による振分けへ固定します。
    /// - Parameters:
    ///   - live: 実終端を処理するPID取得境界。
    ///   - demo: デモ終端を処理するPID取得境界。
    init(live: any OBDPIDTelemetryPort, demo: any OBDPIDTelemetryPort) {
        self.live = live
        self.demo = demo
    }

    /// 終端識別子に対応するPID取得境界を実行します。
    ///
    /// 責務: 1件のPID読取要求群をデモまたは実車の取得処理へ振り分けます。
    /// - Parameters:
    ///   - requests: 読み取るService/PID要求。
    ///   - endpoint: OBDアダプターの接続終端。
    /// - Returns: 選択した境界が返した未加工応答バイト。
    func read(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        if DemoOBDAdapter.matches(endpoint) {
            return try await demo.read(requests, using: endpoint)
        }
        return try await live.read(requests, using: endpoint)
    }

    /// 実終端だけを周期送信対応境界へ振り分けます。
    ///
    /// 責務: 1件の周期取得要求をデモ非対応または実OBD周期取得へ振り分けます。
    /// - Parameters:
    ///   - requests: 周期送信するService/PID要求。
    ///   - endpoint: OBDアダプターの接続終端。
    /// - Returns: 実通信境界が返した未加工応答バイト。
    /// - Throws: デモ終端では周期送信非対応、実終端では注入先のエラー。
    func readPeriodic(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        guard !DemoOBDAdapter.matches(endpoint) else {
            throw OBDPIDTelemetryError.periodicMessagingUnavailable
        }
        return try await live.readPeriodic(requests, using: endpoint)
    }

    /// デモと実通信の両PID取得セッションを終了します。
    ///
    /// 責務: 保持する2件のPID取得境界へ終了要求を伝播します。
    func endSession() async {
        await demo.endSession()
        await live.endSession()
    }
}
