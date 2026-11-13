/// 走行セッションが終了した理由です。
nonisolated enum SessionEndReason: String, Codable, CaseIterable, Sendable {
    /// ユーザーが停止操作をした。
    case userStopped
    /// 車両が応答しなくなった(イグニッションOFFなど)。
    case vehicleNoResponse
    /// アダプターとの接続が切れた。
    case connectionLost
    /// 取得または保存に失敗した。
    case acquisitionFailed
    /// 記録中にアプリが終了し、次回起動時に閉じた。
    case appTerminated
}
