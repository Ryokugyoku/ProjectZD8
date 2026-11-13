import Foundation

/// 開いている整備編集画面の状態です。
nonisolated struct MaintenanceEditorState: Equatable, Sendable {
    /// 未保存の入力です。
    var draft: MaintenanceDraft
    /// 編集開始時点で記録に含まれていた写真IDです。
    let originalPhotoIDs: Set<PhotoID>
    /// 写真IDごとの画像データです。読み込めなかった写真は含みません。
    var photoData: [PhotoID: Data]
    /// 現在の入力が抱える問題です。空なら保存できます。
    var issues: [MaintenanceDraftIssue]
    var isSaving: Bool

    /// 新規作成かどうかです。
    var isNew: Bool { draft.recordID == nil }
}
