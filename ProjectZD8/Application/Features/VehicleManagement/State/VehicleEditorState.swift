import Foundation

/// 開いている車両編集画面の状態です。
nonisolated struct VehicleEditorState: Equatable, Sendable {
    /// 未保存の入力です。
    var draft: VehicleEditDraft
    /// 編集開始時点で保存されていた写真IDです。
    let originalPhotoID: PhotoID?
    /// 現在の写真の画像データです。写真なし、または読み込めない場合は `nil` です。
    var photoData: Data?
    /// 現在の入力が抱える問題です。空なら保存できます。
    var issues: [VehicleEditIssue]
    /// 保存処理中かどうかです。
    var isSaving: Bool
}
