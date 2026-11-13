/// セッションのRawが現在どこにあるかです。
nonisolated enum LogHistoryRawLocation: String, Equatable, Sendable {
    /// この端末にあります。
    case onThisDevice
    /// この端末からは解放済みで、iCloudにだけあります。
    case iCloudOnly

    /// 画面表示に使用するローカライズキーです。
    var nameKey: String { "history.raw.location.\(rawValue)" }

    /// 責務: セッションのRaw所在を表示用の値へ変換します。
    init(_ availability: RawAvailability) {
        switch availability {
        case .local: self = .onThisDevice
        case .cloudOnly: self = .iCloudOnly
        }
    }
}

/// セッションのRawをiCloudへ保存済みかどうかです。
nonisolated enum LogHistoryUploadState: String, Equatable, Sendable {
    /// iCloudへ保存済みです。
    case uploaded
    /// まだiCloudへ保存していません(記録中を含む)。
    case notUploaded

    /// 画面表示に使用するローカライズキーです。
    var nameKey: String { "history.upload.state.\(rawValue)" }
}
