import Foundation

/// 交通規制データの管理画面の、都道府県1行に出す内容です(SwiftUI に依存しない純粋型)。
///
/// - 取り込み中の行は、段階・進み具合・「中止」だけを出し、取得・更新と削除は出しません。
/// - 取り込み中でない行は、取得・更新を出し、取得済みなら削除も出します(押せるかは行の状態に従います)。
/// - 最後の失敗は、取り込み中でない時だけ警告として出します。
nonisolated struct RoadRegulationPrefectureRowContent: Equatable, Sendable {
    /// 都道府県。
    let prefecture: JapanesePrefectureCode
    /// 行の識別子(都道府県コード)。
    let id: Int
    /// 都道府県名の文言キー。
    let nameKey: String
    /// 行の状態の文言キー。
    let statusKey: String
    /// 取得・更新ボタンの文言キー。
    let downloadButtonKey: String
    /// 取得・更新ボタンを出すか(取り込み中でない時)。
    let showsDownload: Bool
    /// 取得・更新ボタンを押せるか。
    let canStartDownload: Bool
    /// 削除ボタンを出すか(取得済みで、この行が取り込み中でない時)。
    let showsRemove: Bool
    /// 削除ボタンを押せるか。
    let canRemove: Bool
    /// 「中止」ボタンを出すか(この行が取り込み中の時)。
    let showsCancel: Bool
    /// 取り込みの段階の文言キー。取り込み中でなければ `nil`。
    let phaseKey: String?
    /// 取り込みの進み具合(0...1)。取り込み中でないか、分からなければ `nil`。
    let progressFraction: Double?
    /// 最後の失敗の文言キー。失敗が無いか、取り込み中なら `nil`。
    let failureKey: String?
    /// 有効な版(基準月・件数・取得日の表示に使う)。未取得なら `nil`。
    let dataset: RoadRegulationDataset?

    /// 都道府県の行から内容を決めます。
    ///
    /// 責務: 行の状態から、出すボタンとその可否・段階・進み具合・失敗の文言キーを決めます。
    /// - Parameters:
    ///   - row: 都道府県の行。
    ///   - textKeys: 文言キーの選択器。
    init(row: RoadRegulationPrefectureRow, textKeys: RoadRegulationSettingsTextKeys = .init()) {
        let isImporting = row.activeImport != nil
        prefecture = row.prefecture
        id = row.id
        nameKey = row.nameKey
        statusKey = textKeys.statusKey(for: row)
        downloadButtonKey = textKeys.downloadButtonKey(for: row)
        showsDownload = !isImporting
        canStartDownload = row.canStartDownload
        showsRemove = row.dataset != nil && !isImporting
        canRemove = row.canRemove
        showsCancel = isImporting
        phaseKey = row.activeImport.map(textKeys.phaseKey(for:))
        progressFraction = row.progressFraction
        failureKey = isImporting ? nil : row.lastFailure.map(textKeys.errorKey(for:))
        dataset = row.dataset
    }
}
