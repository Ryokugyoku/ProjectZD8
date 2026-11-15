import Foundation

/// `ATMA`/`STM` の受信監視を止めるために送る1文字です。
///
/// ELM/STNは受信監視中に何らかの文字を受け取ると監視を止め、`STOPPED` とプロンプトを返してコマンド待ちへ戻ります。
nonisolated struct ELM327MonitorInterruptCommand: Sendable, Equatable, ELM327CommandEncoding {
    /// 未加工観測で使用する安定要求識別子です。
    var requestID: String { "monitorInterrupt" }

    /// 監視を止める復帰文字1バイトです。
    var encodedData: Data { Data("\r".utf8) }
}
