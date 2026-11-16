import Foundation

/// ELM/STNの適応タイミング(`ATAT n`)を設定するコマンドです。
///
/// `ATAT0` で適応タイミングを切ると、アダプターは ECU が応答しても `ATST` のタイムアウト満了まで待ってからプロンプトを返します。
/// 抑止中の見張りで、応答の受信を次の確認の起点にするだけで約1秒周期にするために使います(実アダプターでは未検証)。
/// 受け付けないアダプター(`?` を返す)もあるため、送る側は拒否を失敗にしません。
nonisolated struct ELM327AdaptiveTimingCommand: Sendable, Equatable, ELM327CommandEncoding {
    /// 適応タイミングを切る `ATAT0` です。
    static let off = ELM327AdaptiveTimingCommand(mode: 0)

    /// 設定するモード(0=切、1=既定、2=積極)です。
    let mode: UInt8

    /// 未加工観測で使用する安定要求識別子です。
    var requestID: String { "ATAT\(mode)" }

    /// 復帰文字を付けた送信用ASCIIデータです。
    var encodedData: Data { Data((requestID + "\r").utf8) }
}
