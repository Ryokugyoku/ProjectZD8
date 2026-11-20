/// 返した軌跡の出どころです。
nonisolated enum ConnectionSessionLocationTrackSource: Equatable, Sendable {
    /// この端末で記録したもの。
    case recordedOnThisDevice
    /// 今回 iCloud から取得して復元したもの。
    case downloadedNow
    /// 以前に復元したもの。`isVerifiedLatest` は iCloud と照合して最新と確認できた時だけ true。
    case restoredEarlier(isVerifiedLatest: Bool)
}
