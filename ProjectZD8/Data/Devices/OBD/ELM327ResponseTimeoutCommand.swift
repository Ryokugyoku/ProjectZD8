import Foundation

/// ELM/STNがECU応答を待つアダプター側タイムアウト(`ATST hh`、単位は約4.096ms)を設定するコマンドです。
nonisolated struct ELM327ResponseTimeoutCommand: Sendable, Equatable, ELM327CommandEncoding {
    /// ELM327の既定値 `ATST32`(約200ms)です。
    static let standard = ELM327ResponseTimeoutCommand(value: 0x32)
    /// 設定できる最大値 `ATSTFF`(約1秒)です。
    static let maximum = ELM327ResponseTimeoutCommand(value: 0xFF)

    /// 設定する16進1バイトの値です。
    let value: UInt8

    /// 未加工観測で使用する安定要求識別子です。
    var requestID: String { String(format: "ATST%02X", value) }

    /// 復帰文字を付けた送信用ASCIIデータです。
    var encodedData: Data { Data((requestID + "\r").utf8) }
}
