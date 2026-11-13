/// 1セッションを端末間で受け渡すための完全な内容(属性・取得条件・全Raw)です。
nonisolated struct SessionArchive: Equatable, Codable, Sendable {
    /// アーカイブ形式の現行版です。
    static let currentFormatVersion = 1

    let formatVersion: Int
    let session: DriveSession
    let pids: [SessionPID]
    let samples: [SessionSample]

    /// アーカイブを生成します。
    ///
    /// 責務: 1セッションの全内容を受け渡し単位としてまとめます。
    init(formatVersion: Int = SessionArchive.currentFormatVersion, session: DriveSession, pids: [SessionPID], samples: [SessionSample]) {
        self.formatVersion = formatVersion
        self.session = session
        self.pids = pids
        self.samples = samples
    }
}
