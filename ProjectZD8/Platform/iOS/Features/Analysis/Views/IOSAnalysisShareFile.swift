#if os(iOS)
import Foundation

/// 共有シートへ渡すため、書き出し内容を一時ファイルへ置いたものです。
struct IOSAnalysisShareFile: Identifiable {
    let id: UUID
    let url: URL

    /// 責務: 書き出し内容を一時ディレクトリのファイルへ書きます。書けなければ `nil` です。
    init?(request: AnalysisExportRequest) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(request.id.uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(request.filename)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try request.data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        self.id = request.id
        self.url = url
    }
}
#endif
