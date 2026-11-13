import Foundation

/// セキュリティスコープ付きファイルURLから車両写真を読み込みます。
struct VehiclePhotoFileImporter: VehiclePhotoImportPort {
    /// CloudKit Assetへ渡す前に許容する最大画像容量です。
    private let maximumByteCount: Int

    /// 最大容量を指定して画像読込境界を生成します。
    ///
    /// 責務: 1件の車両写真に許可する最大データ量を固定します。
    /// - Parameter maximumByteCount: 許容する最大バイト数。
    init(maximumByteCount: Int = 20 * 1_024 * 1_024) {
        self.maximumByteCount = maximumByteCount
    }

    /// 指定URLへ一時アクセスして容量内の画像データを返します。
    ///
    /// 責務: 1件の選択ファイルをセキュリティスコープ内で読み込み容量を検証します。
    /// - Parameter url: ファイル選択で許可されたURL。
    /// - Returns: 最大容量以下の画像データ。
    func importPhoto(at url: URL) async throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumByteCount else { throw CocoaError(.fileReadTooLarge) }
        return data
    }
}
