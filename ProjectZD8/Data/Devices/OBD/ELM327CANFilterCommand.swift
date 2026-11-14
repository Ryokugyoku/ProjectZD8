import Foundation

/// CAN監視で受信するフレームのIDフィルター(`ATCF`)です。`ATCM`のマスクと組み合わせて使います。
nonisolated struct ELM327CANFilterCommand: Sendable, ELM327CommandEncoding {
    /// 設定するCAN IDです。
    let identifier: UInt32
    /// IDの値から決めた11bit/29bitの幅です。
    let width: ELM327CANIdentifierWidth

    /// 29bit範囲内のCAN IDだけを受理します。
    ///
    /// 責務: 1件のCAN IDをIDフィルター設定コマンドへ変換します。
    /// - Parameter identifier: `0x7FF`以下は11bit、`0x800...0x1FFFFFFF`は29bitとして扱うCAN ID。
    init?(identifier: UInt32) {
        guard let width = ELM327CANIdentifierWidth(identifier: identifier) else { return nil }
        self.identifier = identifier
        self.width = width
    }

    /// 指定幅に収まるフィルター値だけを受理します。
    ///
    /// 責務: 29bit IDのマスク適用結果が`0x7FF`以下になっても8桁で送れるよう、指定幅で検証して変換します。
    /// - Parameters:
    ///   - identifier: 設定するフィルター値。
    ///   - isExtended: 29bit(8桁)で送るならtrue、11bit(3桁)ならfalse。
    init?(identifier: UInt32, isExtended: Bool) {
        let width = ELM327CANIdentifierWidth(isExtended: isExtended)
        guard width.contains(identifier) else { return nil }
        self.identifier = identifier
        self.width = width
    }

    /// 未加工観測で使用する安定要求識別子です。
    var requestID: String { "ATCF" + width.hexadecimalString(identifier) }

    /// 復帰文字を付けた送信用ASCIIデータです。
    var encodedData: Data { Data((requestID + "\r").utf8) }
}
