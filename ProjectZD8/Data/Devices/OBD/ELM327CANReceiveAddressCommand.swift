import Foundation

/// CAN監視で受信するフレームを1件のCAN IDへ絞るELMの受信アドレス設定(`ATCRA`)です。
nonisolated struct ELM327CANReceiveAddressCommand: Sendable, ELM327CommandEncoding {
    /// 設定するCAN IDです。
    let identifier: UInt32
    /// IDの値から決めた11bit/29bitの幅です。
    let width: ELM327CANIdentifierWidth

    /// 29bit範囲内のCAN IDだけを受理します。
    ///
    /// 責務: 1件のCAN IDを受信アドレス設定コマンドへ変換します。
    /// - Parameter identifier: `0x7FF`以下は11bit、`0x800...0x1FFFFFFF`は29bitとして扱うCAN ID。
    init?(identifier: UInt32) {
        guard let width = ELM327CANIdentifierWidth(identifier: identifier) else { return nil }
        self.identifier = identifier
        self.width = width
    }

    /// 未加工観測で使用する安定要求識別子です。
    var requestID: String { "ATCRA" + width.hexadecimalString(identifier) }

    /// 復帰文字を付けた送信用ASCIIデータです。
    var encodedData: Data { Data((requestID + "\r").utf8) }
}
