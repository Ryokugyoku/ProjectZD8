import Foundation

/// JARTIC の CSV を、Shift-JIS のバイト列のまま行と項目に区切る状態機械です。
///
/// **バイトのまま区切れる根拠**: 区切りに使う ASCII(`,` 0x2C、`"` 0x22、CR 0x0D、LF 0x0A)は、
/// Shift-JIS の2バイト文字の2バイト目(0x40–0x7E、0x80–0xFC)にも1バイト目(0x81–0x9F、0xE0–0xFC)にも現れません。
/// そのため、復号せずにバイトで区切っても漢字を含む項目が途中で切れません。復号は必要な項目だけに後から行います。
///
/// 規則:
/// - R1 `"` で始まる項目は引用付きです。中の `""` は `"` 1文字にします。対になっていない `"` で引用が終わり、
///   その後 `,` か LF までのバイトはそのまま足します(寛容)。
/// - R2 引用なしの項目は `,` か LF までです。途中の `"` はそのまま足します。
/// - R3 引用の外の LF で行が終わります。直前の CR は捨てます。LF だけの改行も受け付けます。
///   引用の外で LF の前でない CR は、項目の中身として残します。ファイル末尾の CR は改行の途中とみなして捨てます。
/// - R4 空行(項目1つで中身が空)は出力しません。
/// - R5 引用の途中でファイルが終わったら `unterminatedQuote` です。末尾に改行のない最後の行は出力します。
/// - R6 1行の長さ(引用符と `,` を含み、行末の CR LF を除いたバイト数)が上限を超えたら `rowTooLong` です。
///   1項目の長さも行の長さを超えないので、この上限で抑えられます(壊れた入力でメモリを使い果たしません)。
///
/// 状態は `consume` の呼び出しをまたいで持ち越すので、チャンクの境目が引用の途中・CR と LF の間・`""` の間に来ても結果は変わりません。
nonisolated struct JARTICCSVTokenizer: Sendable {
    /// 区切りの状態です。
    private enum State: Sendable {
        /// 項目の先頭。
        case fieldStart
        /// 引用なしの項目の途中(引用が閉じた後の寛容な続きも含む)。
        case unquoted
        /// 引用の中。
        case quoted
        /// 引用の中で `"` を読んだ直後(`""` の続きか、引用の終わりか未定)。
        case quoteInQuoted
    }

    /// 1行の長さの上限(バイト)。
    private let maximumRowBytes: Int
    /// 現在の状態。
    private var state: State = .fieldStart
    /// 引用の外で CR を読み、次が LF かどうかを待っている。
    private var hasPendingCarriageReturn = false
    /// 現在の行の項目の中身を連結したバイト列。
    private var rowBytes: [UInt8] = []
    /// 現在の行の、確定した項目の終わりの位置。
    private var fieldEnds: [Int] = []
    /// 現在の行の長さ(行末の CR LF を除くバイト数)。
    private var rowLength = 0

    /// 1行の長さの上限を決めて、空の状態から始めます。
    ///
    /// 責務: 区切りの初期状態を作ります。
    /// - Parameter maximumRowBytes: 1行の長さの上限(バイト)。既定 4 MiB。
    init(maximumRowBytes: Int = 4 << 20) {
        self.maximumRowBytes = maximumRowBytes
    }

    /// 続きのバイト列を区切り、完成した行を順に渡します。
    ///
    /// 責務: 1バイトずつ状態を進めます(入力のバイト数で必ず終わります)。
    /// - Parameters:
    ///   - bytes: 続きのバイト列(どこで切れていてもよい)。
    ///   - emit: 完成した行を受け取る処理。
    /// - Throws: `JARTICCSVError.rowTooLong`。`emit` の失敗はそのまま。
    mutating func consume(_ bytes: UnsafeRawBufferPointer, emit: (JARTICCSVRow) throws -> Void) throws {
        for byte in bytes {
            try accept(byte, emit: emit)
        }
    }

    /// 入力の終わりで、残っている最後の行を渡します。
    ///
    /// 責務: 引用の途中で終わっていないかを確かめ、改行のない最後の行を確定します。終えた後は空の状態に戻ります。
    /// - Parameter emit: 最後の行を受け取る処理。
    /// - Throws: 引用の途中なら `JARTICCSVError.unterminatedQuote`。`emit` の失敗はそのまま。
    mutating func finish(emit: (JARTICCSVRow) throws -> Void) throws {
        guard state != .quoted else { throw JARTICCSVError.unterminatedQuote }
        hasPendingCarriageReturn = false
        let hasPartialRow = state != .fieldStart || !fieldEnds.isEmpty || rowLength > 0
        guard hasPartialRow else { return }
        try endRow(emit: emit)
    }

    /// 1バイトを受け取り、状態に応じて処理します。
    ///
    /// 責務: 保留中の CR を先に片付け、状態ごとの処理へ振り分けます。
    /// - Parameters:
    ///   - byte: 受け取るバイト。
    ///   - emit: 完成した行を受け取る処理。
    /// - Throws: `rowTooLong`。`emit` の失敗。
    private mutating func accept(_ byte: UInt8, emit: (JARTICCSVRow) throws -> Void) throws {
        if hasPendingCarriageReturn {
            hasPendingCarriageReturn = false
            guard byte != Self.lineFeed else { return try endRow(emit: emit) }
            try appendData(Self.carriageReturn)
        }
        switch state {
        case .fieldStart: try acceptAtFieldStart(byte, emit: emit)
        case .unquoted: try acceptUnquoted(byte, emit: emit)
        case .quoted: try acceptQuoted(byte)
        case .quoteInQuoted: try acceptAfterQuoteInQuoted(byte, emit: emit)
        }
    }

    /// 項目の先頭での1バイトを処理します。
    ///
    /// 責務: 引用の開始・空の項目・行の終わり・引用なしの開始を見分けます。
    /// - Parameters:
    ///   - byte: 受け取るバイト。
    ///   - emit: 完成した行を受け取る処理。
    /// - Throws: `rowTooLong`。`emit` の失敗。
    private mutating func acceptAtFieldStart(_ byte: UInt8, emit: (JARTICCSVRow) throws -> Void) throws {
        guard byte == Self.quote else { return try acceptUnquoted(byte, emit: emit) }
        try countRowByte()
        state = .quoted
    }

    /// 引用なしの項目(引用が閉じた後の続きも含む)での1バイトを処理します。
    ///
    /// 責務: `,` で項目を、LF で行を終え、CR は保留し、それ以外は中身に足します(R2・R3)。
    /// - Parameters:
    ///   - byte: 受け取るバイト。
    ///   - emit: 完成した行を受け取る処理。
    /// - Throws: `rowTooLong`。`emit` の失敗。
    private mutating func acceptUnquoted(_ byte: UInt8, emit: (JARTICCSVRow) throws -> Void) throws {
        switch byte {
        case Self.comma:
            try countRowByte()
            endField()
        case Self.lineFeed:
            try endRow(emit: emit)
        case Self.carriageReturn:
            hasPendingCarriageReturn = true
        default:
            try appendData(byte)
        }
    }

    /// 引用の中での1バイトを処理します。
    ///
    /// 責務: `"` で終わり候補へ移り、それ以外(`,`・CR・LF を含む)は中身に足します(R1)。
    /// - Parameter byte: 受け取るバイト。
    /// - Throws: `rowTooLong`。
    private mutating func acceptQuoted(_ byte: UInt8) throws {
        guard byte == Self.quote else { return try appendData(byte) }
        try countRowByte()
        state = .quoteInQuoted
    }

    /// 引用の中で `"` を読んだ直後の1バイトを処理します。
    ///
    /// 責務: `""` なら `"` を足して引用へ戻り、それ以外なら引用を閉じて引用なしの続きとして処理します(R1)。
    /// - Parameters:
    ///   - byte: 受け取るバイト。
    ///   - emit: 完成した行を受け取る処理。
    /// - Throws: `rowTooLong`。`emit` の失敗。
    private mutating func acceptAfterQuoteInQuoted(_ byte: UInt8, emit: (JARTICCSVRow) throws -> Void) throws {
        guard byte == Self.quote else {
            state = .unquoted
            return try acceptUnquoted(byte, emit: emit)
        }
        try countRowByte()
        rowBytes.append(Self.quote)
        state = .quoted
    }

    /// 項目の中身に1バイトを足します。
    ///
    /// 責務: 行の長さを数え、中身に足し、項目の先頭なら引用なしの項目へ移ります。
    /// - Parameter byte: 足すバイト。
    /// - Throws: `rowTooLong`。
    private mutating func appendData(_ byte: UInt8) throws {
        try countRowByte()
        rowBytes.append(byte)
        if state == .fieldStart {
            state = .unquoted
        }
    }

    /// 行の長さを1つ増やし、上限を確かめます。
    ///
    /// 責務: 1行の長さの上限(R6)を守ります。
    /// - Throws: 上限を超えたら `JARTICCSVError.rowTooLong`。
    private mutating func countRowByte() throws {
        rowLength += 1
        guard rowLength <= maximumRowBytes else { throw JARTICCSVError.rowTooLong }
    }

    /// 現在の項目を確定し、次の項目の先頭へ移ります。
    ///
    /// 責務: 項目の終わりの位置を記録します。
    private mutating func endField() {
        fieldEnds.append(rowBytes.count)
        state = .fieldStart
    }

    /// 現在の行を確定し、空行でなければ渡します。
    ///
    /// 責務: 最後の項目を確定し、行の状態を空に戻してから行を渡します(R3・R4)。
    /// - Parameter emit: 完成した行を受け取る処理。
    /// - Throws: `emit` の失敗。
    private mutating func endRow(emit: (JARTICCSVRow) throws -> Void) throws {
        endField()
        let row = JARTICCSVRow(bytes: rowBytes, fieldEnds: fieldEnds)
        rowBytes = []
        fieldEnds = []
        rowLength = 0
        let isBlankRow = row.fieldCount == 1 && row.bytes.isEmpty
        guard !isBlankRow else { return }
        try emit(row)
    }

    /// `"`。
    private static let quote = UInt8(ascii: "\"")
    /// `,`。
    private static let comma = UInt8(ascii: ",")
    /// CR。
    private static let carriageReturn: UInt8 = 0x0D
    /// LF。
    private static let lineFeed: UInt8 = 0x0A
}
