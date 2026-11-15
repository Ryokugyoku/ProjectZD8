import Foundation

/// ELM/STNの加工前応答を評価用の行へ分けます。
nonisolated enum ELM327ResponseLines {
    /// 応答を評価用の行へ分けます。
    ///
    /// 責務: `\r`・`\n` で分割し、プロンプト除去・trim・大文字化を行って空行を除きます。
    /// - Parameter response: 加工前応答。
    /// - Returns: 正規化した空でない行。
    static func normalizedLines(of response: String) -> [String] {
        response.unicodeScalars
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .map { String(String.UnicodeScalarView($0)) }
            .map { $0.replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
    }

    /// 応答がコマンドの拒否(`?`)かどうかを判定します。
    ///
    /// 責務: 正規化した行のいずれかが `?` だけの場合を拒否とします。
    /// - Parameter response: 加工前応答。
    /// - Returns: 拒否なら `true`。
    static func isRejection(_ response: String) -> Bool {
        normalizedLines(of: response).contains("?")
    }
}
