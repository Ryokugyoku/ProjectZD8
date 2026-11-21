import Foundation

/// 交通規制データの管理画面の「更新を確認」の欄に出す内容です(SwiftUI に依存しない純粋型)。
///
/// - 確認中はボタンを押せません。それ以外(未確認・確認済み・失敗)は押せます。
/// - 状態の文言は、未確認なら出しません(ボタンの文言と同じになるため)。確認中・確認済み・失敗なら出します。
/// - 失敗の時だけ、警告として強調します。
nonisolated struct RoadRegulationCatalogHeaderContent: Equatable, Sendable {
    /// 「更新を確認」ボタンの文言キー。
    static let buttonKey = "road_regulation.data.check_updates"

    /// 「更新を確認」ボタンを押せるか。
    let canCheck: Bool
    /// 確認の途中か(進行中の表示を出す)。
    let isChecking: Bool
    /// 状態の文言キー。未確認なら `nil`。
    let statusKey: String?
    /// 確認に失敗したか(警告として強調する)。
    let isFailure: Bool

    /// 一覧の確認の状態から内容を決めます。
    ///
    /// 責務: 確認の状態ごとに、ボタンの可否・進行中の印・状態の文言キー・失敗の印を決めます。
    /// - Parameters:
    ///   - status: 一覧の確認の状態。
    ///   - textKeys: 文言キーの選択器。
    init(status: RoadRegulationCatalogCheckStatus, textKeys: RoadRegulationSettingsTextKeys = .init()) {
        switch status {
        case .notChecked:
            (canCheck, isChecking, statusKey, isFailure) = (true, false, nil, false)
        case .checking:
            (canCheck, isChecking, statusKey, isFailure) = (false, true, textKeys.catalogStatusKey(for: status), false)
        case .checked:
            (canCheck, isChecking, statusKey, isFailure) = (true, false, textKeys.catalogStatusKey(for: status), false)
        case .failed:
            (canCheck, isChecking, statusKey, isFailure) = (true, false, textKeys.catalogStatusKey(for: status), true)
        }
    }
}
