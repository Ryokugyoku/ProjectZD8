import Foundation

/// セキュリティスコープ付きURLから整備写真を読み込みます。
struct MaintenancePhotoFileImporter: MaintenancePhotoImportPort {
    /// 選択URLから写真データを取得します。
    ///
    /// 責務: 1件のファイルURLへの一時アクセスを整備写真データへ変換します。
    /// - Parameter url: Platformが選択した画像ファイルURL。
    /// - Returns: 画像ファイルのバイト列。
    /// - Throws: ファイル読込に失敗した場合のエラー。
    func importPhoto(at url: URL) async throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return try Data(contentsOf: url)
    }
}
