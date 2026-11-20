import Foundation

/// ZIP の中央ディレクトリを最小限に読み、ファイルのエントリの一覧を返します。
///
/// 読み方:
/// 1. ファイル末尾から最大 65,557 B を読み、EOCD を後ろから探します(`ZipEndOfCentralDirectory`)。
/// 2. 中央ディレクトリの46バイトの見出しから、フラグ・方式・CRC・大きさ・ローカル見出しの位置・名前を取ります。
///
/// 名前が `/` で終わるフォルダのエントリは一覧に含めません。暗号化と圧縮方式の検査は展開側(`ZipEntryInflater`)で行います。
nonisolated struct ZipCentralDirectoryReader: Sendable {
    /// 範囲を過不足なく読む部品。
    private let regionReader = ZipFileRegionReader()

    /// 状態を持たない読み取り器を作ります。
    ///
    /// 責務: 中央ディレクトリの読み取り器を構築します。
    init() {}

    /// ZIP ファイルからフォルダ以外のエントリを、中央ディレクトリの順に読みます。
    ///
    /// 責務: EOCD と中央ディレクトリを読み、各エントリの情報へ変換します。
    /// - Parameter file: 読み取る ZIP ファイル。
    /// - Returns: フォルダを除いたエントリの一覧。
    /// - Throws: `ZipArchiveError`(EOCD が無い・ZIP64・分割・中央ディレクトリの矛盾・途中で切れている)。
    func entries(in file: FileHandle) throws -> [ZipArchiveEntry] {
        let fileSize = try regionReader.size(of: file)
        guard fileSize >= UInt64(ZipEndOfCentralDirectory.fixedLength) else { throw ZipArchiveError.notZipArchive }
        let tailLength = min(fileSize, UInt64(ZipEndOfCentralDirectory.maximumSearchLength))
        let tailOffset = fileSize - tailLength
        let tail = try regionReader.read(file, at: tailOffset, count: Int(tailLength))
        let end = try ZipEndOfCentralDirectory.locate(in: tail, tailOffset: tailOffset)
        let directory = try regionReader.read(file, at: end.centralDirectoryOffset, count: Int(end.centralDirectorySize))
        return try parseEntries(ZipLittleEndianBytes(directory), count: end.entryCount).filter { !$0.isDirectory }
    }

    /// 中央ディレクトリのバイト列から、宣言された件数のエントリを順に読みます。
    ///
    /// 責務: 件数ぶんだけ見出しを読み進めます(件数で必ず終わります)。
    /// - Parameters:
    ///   - view: 中央ディレクトリのバイト列。
    ///   - count: EOCD が宣言するエントリ数。
    /// - Returns: フォルダを含む全エントリ。
    /// - Throws: 見出しが壊れていれば `corruptCentralDirectory`、ZIP64 の印は `unsupportedZip64`。
    private func parseEntries(_ view: ZipLittleEndianBytes, count: Int) throws -> [ZipArchiveEntry] {
        var entries: [ZipArchiveEntry] = []
        entries.reserveCapacity(count)
        var position = 0
        for _ in 0..<count {
            let header = try parseHeader(view, at: position)
            entries.append(header.entry)
            position = header.nextPosition
        }
        return entries
    }

    /// 指定位置の中央ディレクトリの見出し1件を読みます。
    ///
    /// 責務: 署名・固定欄・名前を読み、次の見出しの位置を求めます。
    /// - Parameters:
    ///   - view: 中央ディレクトリのバイト列。
    ///   - position: 見出しの位置。
    /// - Returns: 読んだエントリと、次の見出しの位置(必ず46以上進みます)。
    /// - Throws: 署名の不一致・範囲外は `corruptCentralDirectory`、ZIP64 の印は `unsupportedZip64`。
    private func parseHeader(_ view: ZipLittleEndianBytes, at position: Int) throws -> (entry: ZipArchiveEntry, nextPosition: Int) {
        let corrupt = ZipArchiveError.corruptCentralDirectory
        guard view.contains(offset: position, count: Self.headerLength),
              view.uint32(at: position) == Self.headerSignature else { throw corrupt }
        let flags = try view.uint16(at: position + 8, orThrow: corrupt)
        let method = try view.uint16(at: position + 10, orThrow: corrupt)
        let crc = try view.uint32(at: position + 16, orThrow: corrupt)
        let compressed = try view.uint32(at: position + 20, orThrow: corrupt)
        let uncompressed = try view.uint32(at: position + 24, orThrow: corrupt)
        let nameLength = try view.uint16(at: position + 28, orThrow: corrupt)
        let extraLength = try view.uint16(at: position + 30, orThrow: corrupt)
        let commentLength = try view.uint16(at: position + 32, orThrow: corrupt)
        let localOffset = try view.uint32(at: position + 42, orThrow: corrupt)
        guard let name = view.bytes(at: position + Self.headerLength, count: Int(nameLength)) else { throw corrupt }
        guard ![compressed, uncompressed, localOffset].contains(UInt32.max) else { throw ZipArchiveError.unsupportedZip64 }
        let next = position + Self.headerLength + Int(nameLength) + Int(extraLength) + Int(commentLength)
        guard next <= view.bytes.count else { throw ZipArchiveError.corruptCentralDirectory }
        let entry = ZipArchiveEntry(
            pathBytes: name, flags: flags, compressionMethod: method, crc32: crc,
            compressedSize: UInt64(compressed), uncompressedSize: UInt64(uncompressed), localHeaderOffset: UInt64(localOffset)
        )
        return (entry, next)
    }

    /// 中央ディレクトリの見出しの署名 `PK\1\2`。
    private static let headerSignature: UInt32 = 0x0201_4B50
    /// 中央ディレクトリの見出しの固定部分の長さ。
    private static let headerLength = 46
}
