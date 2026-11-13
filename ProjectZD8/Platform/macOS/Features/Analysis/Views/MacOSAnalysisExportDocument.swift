#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Webから届いたCSV・PNGを書き出すための書類です。
nonisolated struct MacOSAnalysisExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .png]

    let data: Data

    /// 責務: 書き出す内容を保持します。
    init(data: Data) {
        self.data = data
    }

    /// 書き出し専用のため、読み込みは常に失敗します。
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    /// 責務: 保持した内容をファイルとして返します。
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
