/// 軌跡の iCloud 取得で起こる失敗です。
nonisolated enum ConnectionSessionLocationTrackCloudError: Error, Equatable, Sendable {
    /// 新しい版のアプリが作ったレコードで、この版では読めない。
    case unsupportedPayloadFormat(version: Int64)
}
