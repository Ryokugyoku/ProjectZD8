import Foundation

/// 交通規制データの管理画面の、都道府県1行の状態です。
///
/// 表示の状態は次の順に決まります(`RoadRegulationSettingsTextKeys.statusKey(for:)`)。
/// 取り込み中 → 失敗して前の版を使用中(失敗があり版がある)→ 更新あり → 取得済み → 未取得。
nonisolated struct RoadRegulationPrefectureRow: Equatable, Sendable, Identifiable {
    /// 都道府県。
    let prefecture: JapanesePrefectureCode
    /// 有効な版。未取得なら `nil`。
    let dataset: RoadRegulationDataset?
    /// 取り込み中の段階。取り込み中でなければ `nil`。
    let activeImport: RoadRegulationImportPhase?
    /// 最後の取り込みの失敗。成功・中止・削除で消えます。
    let lastFailure: RoadRegulationImportError?
    /// 確かめた一覧の公開の印が、手元の版と違うか。
    let isUpdateAvailable: Bool
    /// ほかの県を取り込み中で、この行のボタンを押せないか(同時に取り込めるのは1県だけ)。
    var isBlockedByOtherImport = false

    /// 行の識別子(都道府県コード)。
    var id: Int {
        prefecture.rawValue
    }

    /// 都道府県名の文言キー(`road_regulation.prefecture.01`〜`47`)。
    var nameKey: String {
        "road_regulation.prefecture.\(prefecture.twoDigitText)"
    }

    /// 取り込みの全体の進み具合(0...1。設計書 §3.7)。取り込み中でないか、進み具合が分からなければ `nil`。
    var progressFraction: Double? {
        activeImport.flatMap(RoadRegulationImportProgressFraction().fraction(of:))
    }

    /// 取得・更新のボタンを押せるか(この県もほかの県も取り込み中でない時)。
    var canStartDownload: Bool {
        activeImport == nil && !isBlockedByOtherImport
    }

    /// 削除のボタンを押せるか(取得済みで、どの県も取り込み中でない時)。
    var canRemove: Bool {
        dataset != nil && canStartDownload
    }
}
