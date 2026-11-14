import Foundation

/// CAN監視で`ATCF`のフィルターと比較するビットを指定するELMのIDマスク設定(`ATCM`)です。
nonisolated struct ELM327CANMaskCommand: Sendable, ELM327CommandEncoding {
    /// 比較対象ビットを立てたマスク値です。
    let mask: UInt32
    /// マスクを11bit/29bitどちらの桁数で送るかです。
    let width: ELM327CANIdentifierWidth

    /// 指定幅に収まるマスクだけを受理します。
    ///
    /// 責務: マスク値は値から幅を決められないため、指定された幅で検証してIDマスク設定コマンドへ変換します。
    /// - Parameters:
    ///   - mask: 比較対象ビットを立てたマスク値。
    ///   - isExtended: 29bit(8桁)で送るならtrue、11bit(3桁)ならfalse。
    init?(mask: UInt32, isExtended: Bool) {
        let width = ELM327CANIdentifierWidth(isExtended: isExtended)
        guard width.contains(mask) else { return nil }
        self.mask = mask
        self.width = width
    }

    /// 未加工観測で使用する安定要求識別子です。
    var requestID: String { "ATCM" + width.hexadecimalString(mask) }

    /// 復帰文字を付けた送信用ASCIIデータです。
    var encodedData: Data { Data((requestID + "\r").utf8) }
}
