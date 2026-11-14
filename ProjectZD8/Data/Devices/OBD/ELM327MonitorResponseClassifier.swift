import Foundation

/// `ATMA`送信後に届いた行の列を受信監視の試行結果へ分類します。
nonisolated struct ELM327MonitorResponseClassifier: Sendable {
    /// フレーム行の判定に使うパーサーです。
    private let frameParser = ELM327CANFrameParser()

    /// 行の列を試行結果へ分類します。
    ///
    /// 責務: 無視行を除いて各行の特徴を集め、`BUFFER FULL`・`CAN ERROR`・`?`・フレーム・`STOPPED`の優先順で結果を決めます。
    /// - Parameter lines: `ATMA`送信後に届いた行。
    /// - Returns: 受信監視の試行結果。該当なしは`silent`。
    func classify(_ lines: [String]) -> OBDMonitorProbeOutcome {
        let normalized = lines.map(Self.normalize).filter { !Self.isIgnored($0) }
        if normalized.contains(where: { $0.contains("BUFFER FULL") }) { return .bufferFull }
        if normalized.contains(where: { $0.contains("CAN ERROR") }) { return .busError }
        if normalized.contains("?") { return .unsupported }
        if normalized.contains(where: isFrame) { return .framesReceived }
        if normalized.contains(where: { $0.contains("STOPPED") }) { return .stopped }
        return .silent
    }

    /// 1行が受信フレームとして解釈できるかどうかを判定します。
    ///
    /// 責務: CANフレームパーサーが成功する行だけをフレーム行とします。
    /// - Parameter line: 正規化済みの行。
    /// - Returns: フレーム行ならtrue。
    private func isFrame(_ line: String) -> Bool {
        if case .success = frameParser.parse(line) { return true }
        return false
    }

    /// 1行を評価用に正規化します。
    ///
    /// 責務: プロンプトを除去し、前後の空白を取り除いて大文字化します。
    /// - Parameter line: 届いた行。
    /// - Returns: 正規化した行。
    private static func normalize(_ line: String) -> String {
        line.replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// 正規化済みの行を評価から除くかどうかを判定します。
    ///
    /// 責務: 空行、`SEARCHING`で始まる行、`ATMA`のエコー行を無視対象にします。
    /// - Parameter line: 正規化済みの行。
    /// - Returns: 無視するならtrue。
    private static func isIgnored(_ line: String) -> Bool {
        line.isEmpty || line.hasPrefix("SEARCHING") || line == "ATMA"
    }
}
