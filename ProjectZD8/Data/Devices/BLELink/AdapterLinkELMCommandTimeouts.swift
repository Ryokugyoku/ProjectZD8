/// 常駐リンク上で送るELM/STNコマンドごとの、ホスト側の待機上限です。
///
/// 値の定義場所はここだけです。アダプター側のタイムアウト(`ATST`)は `ELM327ResponseTimeoutCommand` が持ちます。
nonisolated enum AdapterLinkELMCommandTimeouts {
    /// `ATZ` の応答を待つ上限です(再起動に約1秒かかるため長め)。
    static let reset: Duration = .seconds(5)
    /// `ATE0`・`ATL0`・`ATS1`・`ATH0`・`ATH1`・`ATSP0`・`ATST` の応答を待つ上限です。
    static let configuration: Duration = .seconds(2)
    /// `STI`・`ATI`・`ATPPS` の応答を待つ上限です。
    static let identity: Duration = .seconds(2)
    /// `ATMA` 送信後に受信を集める時間窓です。
    static let monitorWindow: Duration = .seconds(2)
    /// 受信監視を止める文字を送った後、プロンプトを待つ上限です。
    static let monitorStop: Duration = .seconds(2)
    /// 通常のタイムアウトでの `0100` の応答を待つ上限です(初回のプロトコル探索 `SEARCHING...` を含む)。
    static let standardVehicleResponse: Duration = .seconds(10)
    /// アダプター側を最大タイムアウトにした `0100` の応答を待つ上限です(各プロトコルが最大約1秒待つ探索を含む)。
    static let adapterMaximumVehicleResponse: Duration = .seconds(30)
    /// `0902` の応答を待つ上限です。
    static let vehicleIdentificationNumber: Duration = .seconds(10)
    /// 常駐リンク上のトランスポートをテレメトリが使うときの1応答の上限です(既存BLEトランスポートと同じ値)。
    static let telemetryResponse: Duration = .seconds(10)
}
