import Foundation

/// テスト用 ZIP の1エントリの指定です(名前・中身・圧縮方式・フラグと、異常系のための差し替え口)。
nonisolated struct TestZipEntrySpec {
    /// 圧縮方式(正しい ZIP を作るための選択)です。
    enum Compression {
        /// 格納(方式0)。
        case stored
        /// deflate(方式8)。
        case deflate
    }

    /// エントリ名。末尾が `/` ならフォルダです。
    var name: String
    /// 名前のバイト列を直接指定する場合の値(UTF-8 でない名前を作る時に使います)。
    var rawNameBytes: [UInt8]?
    /// 展開後の中身。
    var content: [UInt8] = []
    /// 圧縮方式。
    var compression: Compression = .deflate
    /// 名前が UTF-8 であることを示すフラグ 0x800 を立てるか。
    var usesUTF8Flag = false
    /// bit3(データ記述子)を立て、局所ヘッダーの CRC とサイズを 0 にして、データの後ろへ記述子を置くか。
    var usesDataDescriptor = false
    /// 局所ヘッダーの拡張フィールド。
    var localExtraField: [UInt8] = []
    /// 中央ディレクトリの拡張フィールド。
    var centralExtraField: [UInt8] = []
    /// 圧縮データを置き換えるバイト列(壊れたデータを作る時に使い、両ヘッダーの圧縮サイズはこの長さになります)。
    var compressedDataOverride: [UInt8]?
    /// 圧縮データの先頭だけを残す長さ(圧縮データの途中で切れたエントリを作る時に使います)。
    var keepsCompressedPrefix: Int?
    /// 局所ヘッダーの署名を壊すか。
    var corruptsLocalSignature = false
    /// 局所ヘッダーの上書き。
    var local = TestZipFieldOverrides()
    /// 中央ディレクトリの上書き。
    var central = TestZipFieldOverrides()

    /// 責務: 名前だけを指定してエントリを作ります。
    /// - Parameter name: エントリ名。
    init(name: String) {
        self.name = name
    }

    /// 責務: ファイルのエントリを作ります。
    /// - Parameters:
    ///   - name: エントリ名。
    ///   - content: 展開後の中身。
    ///   - compression: 圧縮方式。
    /// - Returns: エントリの指定。
    static func file(_ name: String, _ content: [UInt8], _ compression: Compression = .deflate) -> TestZipEntrySpec {
        var spec = TestZipEntrySpec(name: name)
        spec.content = content
        spec.compression = compression
        return spec
    }

    /// 責務: フォルダのエントリ(格納・0 B)を作ります。
    /// - Parameter name: 末尾が `/` の名前。
    /// - Returns: エントリの指定。
    static func directory(_ name: String) -> TestZipEntrySpec {
        var spec = TestZipEntrySpec(name: name)
        spec.compression = .stored
        return spec
    }
}
