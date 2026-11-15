import Foundation

/// 常駐リンクから届いた受信バイトを、上限付きで溜めてELM/STNプロンプト `>` 単位で取り出すバッファーです。
nonisolated struct AdapterLinkPromptBuffer: Equatable, Sendable {
    /// ELM/STNのコマンド待ちプロンプト `>` のバイト値です。
    static let promptByte: UInt8 = 0x3E

    /// 溜められる最大バイト数です。
    let capacity: Int
    /// まだ取り出していない受信バイトです。
    private(set) var bytes = Data()

    /// 最大バイト数を固定して空のバッファーを生成します。
    ///
    /// 責務: 受信の溜め込み上限を1件の値へ固定します。
    /// - Parameter capacity: 溜められる最大バイト数。1未満は1として扱います。
    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// 受信バイトを末尾へ追加します。
    ///
    /// 責務: 上限を超えない場合だけ受信バイトを届いた順に溜めます。
    /// - Parameter data: 追加する受信バイト。
    /// - Returns: 追加できた場合は `true`。上限を超える場合は追加せず `false`。
    mutating func append(_ data: Data) -> Bool {
        guard bytes.count + data.count <= capacity else { return false }
        bytes.append(data)
        return true
    }

    /// 最初のプロンプトまでを取り出します。
    ///
    /// 責務: 先頭から最初の `>` までを1件の応答として切り出し、残りを次の応答のために残します。
    /// - Returns: `>` を含む応答バイト。プロンプトがまだ無い場合は `nil`。
    mutating func takeThroughPrompt() -> Data? {
        guard let promptIndex = bytes.firstIndex(of: Self.promptByte) else { return nil }
        let end = bytes.index(after: promptIndex)
        let response = Data(bytes[bytes.startIndex..<end])
        bytes = Data(bytes[end...])
        return response
    }

    /// 溜まっている全バイトを取り出します。
    ///
    /// 責務: プロンプトの有無にかかわらず未取り出しの全バイトを返して空にします。
    /// - Returns: 未取り出しの全バイト。
    mutating func takeAll() -> Data {
        let all = bytes
        bytes = Data()
        return all
    }

    /// 溜まっている全バイトを捨てます。
    ///
    /// 責務: 前の利用者や前の応答の残りを次の応答へ混ぜないよう空にします。
    mutating func removeAll() {
        bytes = Data()
    }
}
