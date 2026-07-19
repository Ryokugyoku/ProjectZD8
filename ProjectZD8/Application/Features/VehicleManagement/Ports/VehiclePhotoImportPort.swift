import Foundation

/// Platformが選択した画像URLを同期可能なプロフィールデータへ変換する能力です。
protocol VehiclePhotoImportPort {
    /// 指定URLの画像をプロフィール用データとして読み込みます。
    ///
    /// 責務: ユーザーが選択した画像1件を永続化可能なデータへ変換します。
    /// - Parameter url: Platformのファイル選択結果URL。
    /// - Returns: 読み込みと容量検証を完了した画像データ。
    func importPhoto(at url: URL) async throws -> Data
}
