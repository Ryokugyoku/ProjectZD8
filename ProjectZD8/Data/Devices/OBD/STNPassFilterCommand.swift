import Foundation

/// STN系チップのCAN監視へ通過フィルターを追加するコマンド(`STFAP`)です。
nonisolated struct STNPassFilterCommand: Sendable, ELM327CommandEncoding {
    /// 通過させるCAN IDのパターンです。
    let pattern: UInt32
    /// パターンと比較するビットを立てたマスクです。
    let mask: UInt32
    /// パターンとマスクを11bit/29bitどちらの桁数で送るかです。
    let width: ELM327CANIdentifierWidth

    /// 指定幅に収まるパターンとマスクだけを受理します。
    ///
    /// 責務: パターンとマスクを指定幅で検証し、STN通過フィルター追加コマンドへ変換します。
    /// - Parameters:
    ///   - pattern: 通過させるCAN IDのパターン。
    ///   - mask: 比較対象ビットを立てたマスク。
    ///   - isExtended: 29bit(8桁)で送るならtrue、11bit(3桁)ならfalse。
    init?(pattern: UInt32, mask: UInt32, isExtended: Bool) {
        let width = ELM327CANIdentifierWidth(isExtended: isExtended)
        guard width.contains(pattern), width.contains(mask) else { return nil }
        self.pattern = pattern
        self.mask = mask
        self.width = width
    }

    /// 未加工観測で使用する安定要求識別子です。
    var requestID: String { "STFAP" + width.hexadecimalString(pattern) + "," + width.hexadecimalString(mask) }

    /// 復帰文字を付けた送信用ASCIIデータです。
    var encodedData: Data { Data((requestID + "\r").utf8) }
}
