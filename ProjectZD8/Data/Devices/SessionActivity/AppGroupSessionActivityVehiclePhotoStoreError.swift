/// 記録中表示用の車両写真を保存できなかった理由です。
nonisolated enum AppGroupSessionActivityVehiclePhotoStoreError: Error, Equatable, Sendable {
    /// App Group共有コンテナを開けません(entitlementの不足等)。
    case containerUnavailable
    /// 写真データを画像として読めません。
    case undecodableImage
    /// 縮小した画像をJPEGとして書き出せません。
    case encodingFailed
}
