/// `ATMA`受信監視の1行をCANフレームとして解釈できなかった理由です。
nonisolated enum ELM327CANFrameParseError: Error, Equatable, Sendable {
    /// 行が空、または空白とプロンプトだけでした。
    case emptyLine
    /// CAN IDトークンが16進でない、または桁数が3・8・2桁のいずれでもありませんでした。
    case invalidIdentifier
    /// 2桁区切りの29bit IDに必要な4トークンが揃っていませんでした。
    case missingIdentifier
    /// CAN IDが桁数に対応する幅(11bit/29bit)を超えていました。
    case identifierOutOfRange
    /// データトークンが2桁ではありませんでした。
    case malformedByte
    /// データトークンに16進以外の文字が含まれていました。
    case nonHexadecimalByte
    /// データが9バイト以上ありました。
    case payloadTooLong
}
