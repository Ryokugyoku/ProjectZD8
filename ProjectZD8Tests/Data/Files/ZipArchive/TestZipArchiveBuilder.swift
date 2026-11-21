import Foundation

/// テスト用の ZIP をコードで組み立てます(格納・deflate・UTF-8 の印・フォルダ・bit3 と、異常系のための差し替え口を持ちます)。
///
/// deflate は Compression の raw deflate、CRC32 は `TestZipCRC32`(独立実装)で作ります。
nonisolated struct TestZipArchiveBuilder {
    /// 格納されるエントリの指定。
    var entries: [TestZipEntrySpec]
    /// EOCD の後ろへ付けるコメント。
    var trailingComment: [UInt8] = []
    /// EOCD を書かないか。
    var omitsEndOfCentralDirectory = false
    /// EOCD のディスク番号。
    var endDiskNumber: UInt16 = 0
    /// EOCD のエントリ件数の上書き(0xFFFF で ZIP64 の印になります)。
    var endEntryCountOverride: UInt16?
    /// 中央ディレクトリの先頭の署名を壊すか。
    var corruptsCentralSignature = false

    /// 責務: エントリを指定してビルダーを作ります。
    /// - Parameter entries: エントリの指定。
    init(entries: [TestZipEntrySpec]) {
        self.entries = entries
    }

    /// 1エントリの、書き出す直前の値です。
    private struct Prepared {
        let nameBytes: [UInt8]
        let compressed: [UInt8]
        let crc: UInt32
        let method: UInt16
        let flags: UInt16
    }

    /// 責務: ZIP のバイト列を組み立てます。
    /// - Returns: ZIP 全体のバイト列。
    func build() -> [UInt8] {
        var writer = TestZipByteWriter()
        var offsets: [UInt32] = []
        let prepared = entries.map(prepare)
        for (spec, item) in zip(entries, prepared) {
            offsets.append(UInt32(writer.bytes.count))
            writer.append(localRecord(spec, item))
        }
        let directoryOffset = UInt32(writer.bytes.count)
        var directory = TestZipByteWriter()
        for (index, spec) in entries.enumerated() {
            directory.append(centralRecord(spec, prepared[index], offset: offsets[index]))
        }
        writer.append(directory.bytes)
        if !omitsEndOfCentralDirectory {
            writer.append(endRecord(directorySize: UInt32(directory.bytes.count), directoryOffset: directoryOffset))
        }
        return writer.bytes
    }

    /// 責務: 1エントリの名前・圧縮データ・CRC・方式・既定のフラグを決めます。
    private func prepare(_ spec: TestZipEntrySpec) -> Prepared {
        var compressed = spec.compression == .deflate ? TestZipRawDeflate.compress(spec.content) : spec.content
        if let prefix = spec.keepsCompressedPrefix { compressed = Array(compressed.prefix(prefix)) }
        if let replacement = spec.compressedDataOverride { compressed = replacement }
        var flags: UInt16 = spec.usesUTF8Flag ? 0x0800 : 0
        if spec.usesDataDescriptor { flags |= 0x0008 }
        return Prepared(
            nameBytes: spec.rawNameBytes ?? Array(spec.name.utf8),
            compressed: compressed,
            crc: TestZipCRC32.checksum(spec.content),
            method: spec.compression == .deflate ? 8 : 0,
            flags: flags
        )
    }

    /// 責務: 局所ヘッダー・名前・拡張・圧縮データ(と、あればデータ記述子)を並べます。
    private func localRecord(_ spec: TestZipEntrySpec, _ item: Prepared) -> [UInt8] {
        let overrides = spec.local
        let crc = overrides.crc ?? (spec.usesDataDescriptor ? 0 : item.crc)
        let compressedSize = overrides.compressedSize ?? (spec.usesDataDescriptor ? 0 : UInt32(item.compressed.count))
        let uncompressedSize = overrides.uncompressedSize ?? (spec.usesDataDescriptor ? 0 : UInt32(spec.content.count))
        var writer = TestZipByteWriter()
        writer.append32(spec.corruptsLocalSignature ? 0x0403_4B51 : 0x0403_4B50)
        writer.append16(20)
        writer.append16(overrides.flags ?? item.flags)
        writer.append16(overrides.method ?? item.method)
        writer.append16(0)
        writer.append16(0x0021)
        writer.append32(crc)
        writer.append32(compressedSize)
        writer.append32(uncompressedSize)
        writer.append16(UInt16(item.nameBytes.count))
        writer.append16(UInt16(spec.localExtraField.count))
        writer.append(item.nameBytes)
        writer.append(spec.localExtraField)
        writer.append(item.compressed)
        if spec.usesDataDescriptor {
            writer.append32(0x0807_4B50)
            writer.append32(item.crc)
            writer.append32(UInt32(item.compressed.count))
            writer.append32(UInt32(spec.content.count))
        }
        return writer.bytes
    }

    /// 責務: 中央ディレクトリの見出し1件(46 B + 名前 + 拡張)を作ります。
    private func centralRecord(_ spec: TestZipEntrySpec, _ item: Prepared, offset: UInt32) -> [UInt8] {
        let overrides = spec.central
        var writer = TestZipByteWriter()
        writer.append32(corruptsCentralSignature ? 0x0201_4B51 : 0x0201_4B50)
        writer.append16(20)
        writer.append16(20)
        writer.append16(overrides.flags ?? item.flags)
        writer.append16(overrides.method ?? item.method)
        writer.append16(0)
        writer.append16(0x0021)
        writer.append32(overrides.crc ?? item.crc)
        writer.append32(overrides.compressedSize ?? UInt32(item.compressed.count))
        writer.append32(overrides.uncompressedSize ?? UInt32(spec.content.count))
        writer.append16(UInt16(item.nameBytes.count))
        writer.append16(UInt16(spec.centralExtraField.count))
        writer.append16(0)
        writer.append16(0)
        writer.append16(0)
        writer.append32(0)
        writer.append32(overrides.localHeaderOffset ?? offset)
        writer.append(item.nameBytes)
        writer.append(spec.centralExtraField)
        return writer.bytes
    }

    /// 責務: EOCD(22 B + コメント)を作ります。
    private func endRecord(directorySize: UInt32, directoryOffset: UInt32) -> [UInt8] {
        var writer = TestZipByteWriter()
        let count = endEntryCountOverride ?? UInt16(entries.count)
        writer.append32(0x0605_4B50)
        writer.append16(endDiskNumber)
        writer.append16(0)
        writer.append16(count)
        writer.append16(count)
        writer.append32(directorySize)
        writer.append32(directoryOffset)
        writer.append16(UInt16(trailingComment.count))
        writer.append(trailingComment)
        return writer.bytes
    }
}
