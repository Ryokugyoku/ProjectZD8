/// 1回のOBD接続で指定PIDの未加工データを読み取る能力です。
protocol OBDPIDTelemetryPort: Sendable {
    /// 複数要求を順番に実行し、送信後の結果を要求単位で返します。
    ///
    /// 責務: PID要求群を推測を含まないTransport観測列へ変換します。
    /// - Parameters:
    ///   - requests: 読み取るService/PID要求。
    ///   - endpoint: OBDアダプターの物理終端。
    /// - Returns: 実際に送信開始した要求ごとのTransport観測。
    /// - Throws: 要求送信前の定義、接続、または初期化失敗。
    func readObservations(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequestTransportObservation]

    /// 複数の読取要求を1回の物理接続で実行します。
    ///
    /// 責務: 許可済みService/PID要求群を未加工応答バイトへ変換します。
    /// - Parameters:
    ///   - requests: 読み取るService/PID要求。
    ///   - endpoint: OBDアダプターの物理終端。
    /// - Returns: 要求ごとの未加工データバイト。
    /// - Throws: 非対応PID、接続、拒否応答、または形式不正の場合のエラー。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]]

    /// 車両型式と送信ヘッダーが確認済みの専用PIDを読み取ります。
    ///
    /// 責務: 型式適用済みPID定義群を物理ECU指定の未加工応答へ変換します。
    /// - Parameters:
    ///   - definitions: 型式と11bit送信ヘッダーを持つ専用PID定義。
    ///   - endpoint: OBDアダプターの物理終端。
    /// - Returns: 応答が確認できたService/PIDごとの未加工データバイト。
    /// - Throws: ヘッダー不正、非対応通信、拒否応答、または接続失敗の場合のエラー。
    func readVehicleSpecific(
        _ definitions: [OBDPIDDefinition],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]]

    /// 現在の継続取得セッションを終了します。
    ///
    /// 責務: PID取得境界が保持する接続資源を再利用不能な終了状態へ遷移させます。
    func endSession() async
}

/// セッション資源を保持しないPID取得境界へ既定終了動作を提供します。
extension OBDPIDTelemetryPort {
    /// 辞書型の既存実装から正応答だけを要求単位へ変換します。
    ///
    /// 責務: typed観測未実装の境界へ後方互換な観測列を提供します。
    /// - Parameters:
    ///   - requests: 読み取るService/PID要求。
    ///   - endpoint: OBDアダプターの物理終端。
    /// - Returns: 既存境界がpayloadを返した要求だけの入力順観測列。
    /// - Throws: 既存の一括読取が送出したエラー。
    func readObservations(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequestTransportObservation] {
        let responses = try await read(requests, using: endpoint)
        return requests.compactMap { request in
            responses[request].map { payload in
                OBDPIDRequestTransportObservation(request: request, outcome: .responded(payload))
            }
        }
    }

    /// 専用PID通信を実装しない境界では明示的な非対応を返します。
    ///
    /// 責務: 任意実装の車種専用PID要求を安全な非対応結果へ変換します。
    /// - Parameters:
    ///   - definitions: 実行しない専用PID定義。
    ///   - endpoint: 使用しないOBD終端。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `OBDPIDTelemetryError.unsupportedPID`。
    func readVehicleSpecific(
        _ definitions: [OBDPIDDefinition],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        throw OBDPIDTelemetryError.unsupportedPID
    }

    /// 保持資源がない取得境界では終了要求を変更なしで完了します。
    ///
    /// 責務: ステートレスなPID取得実装へ副作用のない終了動作を提供します。
    func endSession() async {}
}
