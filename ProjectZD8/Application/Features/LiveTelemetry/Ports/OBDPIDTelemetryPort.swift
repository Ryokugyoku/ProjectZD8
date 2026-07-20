/// 1回のOBD接続で指定PIDの未加工データを読み取る能力です。
protocol OBDPIDTelemetryPort: Sendable {
    /// 複数の読取要求を1回の物理接続で実行します。
    ///
    /// 責務: 許可済みService/PID要求群を未加工応答バイトへ変換します。
    /// - Parameters:
    ///   - requests: 読み取るService/PID要求。
    ///   - endpoint: OBDアダプターの物理終端。
    /// - Returns: 要求ごとの未加工データバイト。
    /// - Throws: 非対応PID、接続、拒否応答、または形式不正の場合のエラー。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]]

    /// アダプターへ周期送信を委譲して次の応答群を読み取ります。
    ///
    /// 責務: 許可済みService/PID要求群をアダプター管理の周期応答バイトへ変換します。
    /// - Parameters:
    ///   - requests: 周期送信する読取り専用Service/PID要求。
    ///   - endpoint: OBDアダプターの物理終端。
    /// - Returns: 今回受信できた要求ごとの未加工応答バイト。
    /// - Throws: 周期送信非対応、接続、拒否応答、または形式不正の場合のエラー。
    func readPeriodic(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]]

    /// 現在の継続取得セッションを終了します。
    ///
    /// 責務: PID取得境界が保持する接続資源を再利用不能な終了状態へ遷移させます。
    func endSession() async
}

/// セッション資源を保持しないPID取得境界へ既定終了動作を提供します。
extension OBDPIDTelemetryPort {
    /// 周期送信を実装しない境界では明示的な非対応を返します。
    ///
    /// 責務: 任意実装の周期取得要求を安全な非対応結果へ変換します。
    /// - Parameters:
    ///   - requests: 周期取得を要求されたService/PID。
    ///   - endpoint: 要求されたOBD終端。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `OBDPIDTelemetryError.periodicMessagingUnavailable`。
    func readPeriodic(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        throw OBDPIDTelemetryError.periodicMessagingUnavailable
    }

    /// 保持資源がない取得境界では終了要求を変更なしで完了します。
    ///
    /// 責務: ステートレスなPID取得実装へ副作用のない終了動作を提供します。
    func endSession() async {}
}
