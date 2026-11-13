/// どのチャンネルからも応答が得られなかった区間です。
nonisolated struct AnalysisGap: Codable, Equatable, Sendable {
    /// 区間の開始(セッション開始からの秒)です。
    let startSeconds: Double
    /// 区間の終了(セッション開始からの秒)です。
    let endSeconds: Double

    /// 区間の長さ(秒)です。
    var durationSeconds: Double { endSeconds - startSeconds }
}
