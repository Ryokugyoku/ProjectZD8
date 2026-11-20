import Foundation

/// 形状の BLOB をリトルエンディアンの整数として先頭から読みます。
nonisolated struct RoadRegulationGeometryBlobReader {
    /// 読み取るバイト列です。
    private let bytes: [UInt8]
    /// 次に読む位置です。
    private var offset = 0

    /// 読み取るバイト列を保持して生成します。
    ///
    /// 責務: 先頭から読む状態を作ります。
    /// - Parameter bytes: 読み取るバイト列。
    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// 残りのバイト数です。
    var remainingCount: Int {
        bytes.count - offset
    }

    /// すべて読み終えたかどうかです。
    var isAtEnd: Bool {
        offset == bytes.count
    }

    /// 1バイトの符号なし整数を読みます。
    ///
    /// 責務: 1バイトを読み進めます。
    /// - Returns: 読んだ値。
    /// - Throws: 残りが足りない場合は `RoadRegulationRepositoryError.integrityConflict`。
    mutating func readUInt8() throws -> UInt8 {
        try read(UInt8.self)
    }

    /// 2バイトの符号なし整数を読みます。
    ///
    /// 責務: リトルエンディアンの2バイトを読み進めます。
    /// - Returns: 読んだ値。
    /// - Throws: 残りが足りない場合は `RoadRegulationRepositoryError.integrityConflict`。
    mutating func readUInt16() throws -> UInt16 {
        try read(UInt16.self)
    }

    /// 4バイトの符号なし整数を読みます。
    ///
    /// 責務: リトルエンディアンの4バイトを読み進めます。
    /// - Returns: 読んだ値。
    /// - Throws: 残りが足りない場合は `RoadRegulationRepositoryError.integrityConflict`。
    mutating func readUInt32() throws -> UInt32 {
        try read(UInt32.self)
    }

    /// 4バイトの符号つき整数を読みます。
    ///
    /// 責務: リトルエンディアンの4バイトを2の補数として読み進めます。
    /// - Returns: 読んだ値。
    /// - Throws: 残りが足りない場合は `RoadRegulationRepositoryError.integrityConflict`。
    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try read(UInt32.self))
    }

    /// 固定長の符号なし整数を読みます。
    ///
    /// 責務: 型の大きさだけのバイトを下位から組み立て、位置を進めます。
    /// - Parameter type: 読む整数の型。
    /// - Returns: 読んだ値。
    /// - Throws: 残りが足りない場合は `RoadRegulationRepositoryError.integrityConflict`。
    private mutating func read<Value: FixedWidthInteger & UnsignedInteger>(_ type: Value.Type) throws -> Value {
        let size = MemoryLayout<Value>.size
        guard remainingCount >= size else { throw RoadRegulationRepositoryError.integrityConflict }
        var value: Value = 0
        for index in 0..<size {
            value |= Value(bytes[offset + index]) << (8 * index)
        }
        offset += size
        return value
    }
}
