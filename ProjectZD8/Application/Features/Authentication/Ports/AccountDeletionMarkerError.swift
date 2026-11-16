/// 削除済みの印を理由に、アップロードや保存を行わなかったことを表します。
enum AccountDeletionMarkerError: Error, Equatable {
    /// アカウントが他端末で削除済みであるため、アップロード・保存を行いませんでした。
    case accountDeleted
}
