/// 記録中表示の処理のうち、失敗を診断へ残す操作の種類です。
nonisolated enum RecordingSessionActivityOperation: Equatable, Sendable {
    /// 表示の開始です。
    case start
    /// 表示内容の更新です。
    case update
    /// 最終内容を出して閉じる終了です。
    case end
    /// 車両写真の保存です。失敗しても写真なしで表示を続けます。
    case storePhoto
    /// 車両写真の削除です。
    case removePhotos
}
