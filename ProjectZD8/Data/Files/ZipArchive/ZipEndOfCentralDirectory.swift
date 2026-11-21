import Foundation

/// ZIP の終端の見出し(EOCD、`PK\5\6`)から読んだ、中央ディレクトリの位置と件数です。
///
/// ZIP64 と分割 ZIP はここで拒否します。
nonisolated struct ZipEndOfCentralDirectory: Equatable, Sendable {
    /// 中央ディレクトリのエントリ数。
    let entryCount: Int
    /// 中央ディレクトリの大きさ(バイト)。
    let centralDirectorySize: UInt64
    /// 中央ディレクトリの、ファイル先頭からの位置。
    let centralDirectoryOffset: UInt64

    /// EOCD の固定部分の長さ。
    static let fixedLength = 22
    /// ファイル末尾から探す最大の長さ(固定部分 + コメント最大 65,535 B)。
    static let maximumSearchLength = 65_557

    /// ファイル末尾のバイト列から EOCD を後ろ向きに探して読みます。
    ///
    /// 責務: 署名の位置を決め、ZIP64・分割・範囲の矛盾を検査した EOCD を返します。
    /// - Parameters:
    ///   - tail: ファイル末尾のバイト列(最大 `maximumSearchLength`)。
    ///   - tailOffset: `tail` の先頭の、ファイル先頭からの位置。
    /// - Returns: 検査済みの EOCD。
    /// - Throws: 署名が無ければ `notZipArchive`。ZIP64 は `unsupportedZip64`、分割は `multiDiskUnsupported`、
    ///   中央ディレクトリが EOCD より後ろへはみ出すなら `corruptCentralDirectory`。
    static func locate(in tail: [UInt8], tailOffset: UInt64) throws -> ZipEndOfCentralDirectory {
        let view = ZipLittleEndianBytes(tail)
        guard let position = signaturePosition(in: view) else { throw ZipArchiveError.notZipArchive }
        try rejectZip64Locator(in: view, before: position)
        let record = try parse(view, at: position)
        guard record.centralDirectoryOffset + record.centralDirectorySize <= tailOffset + UInt64(position) else {
            throw ZipArchiveError.corruptCentralDirectory
        }
        return record
    }

    /// EOCD の署名を末尾から先頭へ向かって探します。
    ///
    /// 責務: コメント長と矛盾しない、最も後ろの署名の位置を返します。
    /// - Parameter view: ファイル末尾のバイト列。
    /// - Returns: 署名の位置。無ければ `nil`。
    private static func signaturePosition(in view: ZipLittleEndianBytes) -> Int? {
        guard view.bytes.count >= fixedLength else { return nil }
        for position in stride(from: view.bytes.count - fixedLength, through: 0, by: -1) where isRecord(in: view, at: position) {
            return position
        }
        return nil
    }

    /// 指定位置が、コメント長まで含めて末尾に収まる EOCD かを判定します。
    ///
    /// 責務: 署名とコメント長の整合を確かめます。
    /// - Parameters:
    ///   - view: ファイル末尾のバイト列。
    ///   - position: 調べる位置。
    /// - Returns: EOCD として読めるなら `true`。
    private static func isRecord(in view: ZipLittleEndianBytes, at position: Int) -> Bool {
        guard view.uint32(at: position) == signature,
              let commentLength = view.uint16(at: position + 20) else { return false }
        return view.contains(offset: position + fixedLength, count: Int(commentLength))
    }

    /// EOCD の直前に ZIP64 の終端位置(`PK\6\7`)があれば拒否します。
    ///
    /// 責務: 値が 0xFFFF でない ZIP64 の書き方も見落とさないようにします。
    /// - Parameters:
    ///   - view: ファイル末尾のバイト列。
    ///   - position: EOCD の位置。
    /// - Throws: ZIP64 の終端位置があれば `unsupportedZip64`。
    private static func rejectZip64Locator(in view: ZipLittleEndianBytes, before position: Int) throws {
        let locatorPosition = position - zip64LocatorLength
        guard locatorPosition >= 0, view.uint32(at: locatorPosition) == zip64LocatorSignature else { return }
        throw ZipArchiveError.unsupportedZip64
    }

    /// EOCD の各欄を読み、ZIP64 と分割を検査します。
    ///
    /// 責務: 固定部分の欄を値の型へ写します。
    /// - Parameters:
    ///   - view: ファイル末尾のバイト列。
    ///   - position: EOCD の位置。
    /// - Returns: 読んだ EOCD。
    /// - Throws: ZIP64 の印は `unsupportedZip64`、ディスク番号の不一致は `multiDiskUnsupported`。
    private static func parse(_ view: ZipLittleEndianBytes, at position: Int) throws -> ZipEndOfCentralDirectory {
        let invalid = ZipArchiveError.notZipArchive
        let diskNumber = try view.uint16(at: position + 4, orThrow: invalid)
        let directoryDisk = try view.uint16(at: position + 6, orThrow: invalid)
        let entriesOnDisk = try view.uint16(at: position + 8, orThrow: invalid)
        let totalEntries = try view.uint16(at: position + 10, orThrow: invalid)
        let size = try view.uint32(at: position + 12, orThrow: invalid)
        let offset = try view.uint32(at: position + 16, orThrow: invalid)
        let usesZip64 = [entriesOnDisk, totalEntries].contains(UInt16.max) || [size, offset].contains(UInt32.max)
        guard !usesZip64 else { throw ZipArchiveError.unsupportedZip64 }
        guard diskNumber == 0, directoryDisk == 0, entriesOnDisk == totalEntries else {
            throw ZipArchiveError.multiDiskUnsupported
        }
        return ZipEndOfCentralDirectory(
            entryCount: Int(totalEntries),
            centralDirectorySize: UInt64(size),
            centralDirectoryOffset: UInt64(offset)
        )
    }

    /// EOCD の署名 `PK\5\6`。
    private static let signature: UInt32 = 0x0605_4B50
    /// ZIP64 の終端位置の署名 `PK\6\7`。
    private static let zip64LocatorSignature: UInt32 = 0x0706_4B50
    /// ZIP64 の終端位置の長さ。
    private static let zip64LocatorLength = 20
}
