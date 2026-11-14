import Foundation

/// Raw件数とバイト数を含む alert 本文を表示文字列へ変換します。
///
/// ローカライズ解決、バイト数表記、書式ロケールを注入でき、既定値は従来の View と同じ挙動です。
struct ConnectionHistoryRawSummaryMessageFormatter {
    /// ローカライズキーを書式文字列へ解決します。
    let localizedFormat: (String) -> String
    /// 非負のバイト数を表示用の容量文字列へ変換します。
    let byteCountText: (Int64) -> String
    /// 件数と容量を書式へ埋め込む時のロケールです。
    let locale: Locale

    /// ローカライズ解決、容量表記、ロケールを固定して生成します。
    ///
    /// 責務: Raw集計本文の整形に使うロケール依存の処理を1組にまとめます。
    /// - Parameters:
    ///   - localizedFormat: ローカライズキーを書式文字列へ解決する処理。既定は String Catalog の参照。
    ///   - byteCountText: バイト数を容量文字列へ変換する処理。既定は `ByteCountFormatter` の `.file` 表記。
    ///   - locale: 書式へ値を埋め込む時のロケール。既定は自動更新の現在ロケール。
    init(
        localizedFormat: @escaping (String) -> String = { String(localized: String.LocalizationValue($0)) },
        byteCountText: @escaping (Int64) -> String = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
        locale: Locale = .autoupdatingCurrent
    ) {
        self.localizedFormat = localizedFormat
        self.byteCountText = byteCountText
        self.locale = locale
    }

    /// Raw件数と容量を書式付き文言へ埋め込みます。
    ///
    /// 責務: 1件の書式キー、件数、バイト数を、負のバイト数を0とした警告本文へ変換します。
    /// - Parameters:
    ///   - formatKey: `%lld` と `%@` を含む書式のローカライズキー。
    ///   - recordCount: 本文へ埋め込むRaw件数。
    ///   - byteCount: 本文へ埋め込むRaw合計バイト数。負値は0として扱います。
    /// - Returns: 件数と容量を含むユーザー向け本文。
    func text(formatKey: String, recordCount: Int64, byteCount: Int64) -> String {
        let format = localizedFormat(formatKey)
        let bytes = byteCountText(max(0, byteCount))
        return String(format: format, locale: locale, recordCount, bytes)
    }
}
