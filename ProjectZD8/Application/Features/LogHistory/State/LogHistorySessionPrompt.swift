import Foundation

/// 削除または領域解放の確認画面へ表示するセッション情報です。
nonisolated struct LogHistorySessionPrompt: Equatable, Sendable {
    let sessionID: SessionID
    let vehicleName: String?
    let startedAt: Date
    let sampleCount: Int
    let payloadByteCount: Int

    /// 応答ペイロード合計の表示用文字列です。
    var payloadSizeText: String { Int64(payloadByteCount).formatted(.byteCount(style: .file)) }
}
