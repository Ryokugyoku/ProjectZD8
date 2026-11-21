import Foundation

/// 交通規制データの管理画面から送る操作です。
enum RoadRegulationSettingsAction: Equatable {
    /// 画面が表示された。
    case appeared
    /// 「更新を確認」が押された。
    case checkUpdatesRequested
    /// 都道府県の取得・更新が押された。
    case downloadRequested(JapanesePrefectureCode)
    /// 取得中の中止が押された。
    case cancelRequested
    /// 都道府県の削除が押された(確認前)。
    case removeRequested(JapanesePrefectureCode)
    /// 削除の確認で「削除」が選ばれた。
    case removeConfirmed
    /// 削除の確認が取り消された。
    case removeCancelled
    /// 表示中のエラーが閉じられた。
    case errorDismissed
}
