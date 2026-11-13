/// アダプターとの通信路を開く契約です。`AdapterTransport.demo` には模擬リンクを返します。
nonisolated protocol OBDLinkPort: Sendable {
    /// 責務: アダプターへ接続し、ELM327の初期化まで済ませたリンクを返します。
    /// - Throws: 接続または初期化に失敗した場合の `OBDLinkError`。
    func open(_ adapter: AdapterDescriptor) async throws -> any OBDLink
}

/// 初期化済みの1本のOBD通信路です。要求は直列に処理します。
nonisolated protocol OBDLink: Sendable {
    /// 責務: アダプター情報・VIN・通信プロトコルを読み取ります。
    func identify() async throws -> VehicleIdentification
    /// 責務: サービス01の対応ビットマップを辿り、車両が対応するPIDを返します。
    func supportedPIDs() async throws -> Set<OBDPIDRequest>
    /// 責務: 1件のPIDを要求して結果を返します。`header` が `nil` なら標準の機能アドレスへ送ります。
    /// - Throws: 通信路が使えなくなった場合だけ `OBDLinkError` を投げます。個々の無応答は結果として返します。
    func query(_ request: OBDPIDRequest, header: UInt16?) async throws -> OBDQueryResult
    /// 責務: 通信路を閉じます。以後の要求は `OBDLinkError.connectionLost` になります。
    func close() async
}

/// 1件のPID要求の結果です。
nonisolated struct OBDQueryResult: Equatable, Sendable {
    let outcome: SampleOutcome
    /// サービス・PIDのエコーを除いた応答データです。`responded` 以外では空です。
    let payload: [UInt8]

    /// 責務: 要求結果を生成します。
    init(outcome: SampleOutcome, payload: [UInt8] = []) {
        self.outcome = outcome
        self.payload = payload
    }
}

/// 通信路の失敗です。
nonisolated enum OBDLinkError: Error, Equatable, Sendable {
    /// この端末では使えない通信経路だった。
    case transportUnsupported
    /// アダプターへ接続できなかった。
    case connectionFailed
    /// アダプターが初期化コマンドを拒否した、または想定外の応答を返した。
    case adapterRejected
    /// 接続後に通信が切れた。
    case connectionLost
    /// 応答がタイムアウトした。
    case timedOut
    /// 車両がVINを返さなかった。
    case vinUnavailable
}
