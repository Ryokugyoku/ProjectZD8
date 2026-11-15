/// `ATMA`による受信監視の試行応答を分類した結果です。
///
/// `rawValue` は取得証跡へ保存する安定文字列です。case名を変える場合は保存値を維持してください。
nonisolated enum OBDMonitorProbeOutcome: String, Equatable, Sendable {
    /// CANフレームを1件以上受信しました。
    case framesReceived
    /// アダプターが`ATMA`を受け付けませんでした。
    case unsupported
    /// 受信量がアダプターのバッファーを超えました。
    case bufferFull
    /// フレームを受信しませんでした。
    case silent
    /// CANバスのエラーを報告しました。
    case busError
    /// フレームを受信しないまま監視が停止しました。
    case stopped
}
