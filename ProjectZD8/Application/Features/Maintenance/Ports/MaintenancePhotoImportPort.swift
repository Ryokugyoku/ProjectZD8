import Foundation

/// ユーザーが選択した写真を整備エビデンス用データへ読み込む能力です。
protocol MaintenancePhotoImportPort: Sendable {
    /// 指定URLの画像データを読み込みます。
    ///
    /// 責務: 1件の選択ファイルを整備写真へ保存可能なデータへ変換します。
    /// - Parameter url: Platformのファイル選択で得たURL。
    /// - Returns: 読み込んだ画像データ。
    /// - Throws: アクセスまたは読込に失敗した場合のエラー。
    func importPhoto(at url: URL) async throws -> Data
}
