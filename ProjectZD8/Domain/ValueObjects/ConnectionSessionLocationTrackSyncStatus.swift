/// 軌跡の同期状態です。水位の比較から導出します。
nonisolated enum ConnectionSessionLocationTrackSyncStatus: Equatable, Sendable {
    /// ローカルに軌跡が無く、送るものが無い。
    case nothingToSync
    /// 軌跡はあるが未送信。
    case notUploaded
    /// 送信済みで変化なし。
    case uploaded(manifestDigest: String)
    /// 送信後に点や事象が増えた。
    case changedSinceUpload(previousDigest: String)
    /// iCloud から復元したもの。
    case restoredFromCloud(manifestDigest: String)

    /// 送信が必要な時に true。`notUploaded` と `changedSinceUpload` だけが対象。
    var needsUpload: Bool {
        switch self {
        case .notUploaded, .changedSinceUpload:
            return true
        case .nothingToSync, .uploaded, .restoredFromCloud:
            return false
        }
    }
}
