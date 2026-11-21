import Foundation

/// 照合の結果と一覧の行から、カードに添える注記を選びます。
///
/// 並びは「車速なし(iCloud / 記録なし)」→「範囲外」→「指定なしの説明」で、該当するものだけを入れます。
nonisolated struct SessionRoadRegulationReviewNoticeBuilder: Sendable {
    /// 状態を持たない選択器を作ります。
    ///
    /// 責務: 規則だけで注記を選ぶ選択器を用意します。
    init() {}

    /// 注記を選びます。
    ///
    /// 責務: 車速の有無と Raw の置き場所、版の有無と範囲外の行、指定なしの行から、該当する注記を順に並べます。
    /// - Parameters:
    ///   - review: 照合の結果。
    ///   - rows: 一覧の行。
    ///   - rawLog: 評価に使った Raw の置き場所。
    /// - Returns: 注記(0〜3件)。
    func notices(
        review: SessionRoadRegulationReview,
        rows: [SessionRoadRegulationReviewRow],
        rawLog: SessionRoadRegulationRawLogAvailability
    ) -> [SessionRoadRegulationReviewNotice] {
        [
            speedNotice(hasVehicleSpeed: review.hasVehicleSpeed, rawLog: rawLog),
            outsideDataNotice(review: review, rows: rows),
            rows.contains { $0.outcome == .unregulated } ? .unregulatedExplained : nil,
        ].compactMap { $0 }
    }

    /// 車速の記録が無い時の注記を選びます。
    ///
    /// 責務: 車速があれば `nil`、無ければ Raw が iCloud にあるかで注記を選びます。
    /// - Parameters:
    ///   - hasVehicleSpeed: 車速の記録があるか。
    ///   - rawLog: 評価に使った Raw の置き場所。
    /// - Returns: 注記。車速があれば `nil`。
    private func speedNotice(hasVehicleSpeed: Bool, rawLog: SessionRoadRegulationRawLogAvailability) -> SessionRoadRegulationReviewNotice? {
        guard !hasVehicleSpeed else { return nil }
        return rawLog == .inCloud ? .speedInCloud : .speedNotRecorded
    }

    /// 規制データの範囲外の注記を選びます。
    ///
    /// 責務: 使った版が無い、または範囲外の理由で判定できない行がある時だけ注記を返します。
    /// - Parameters:
    ///   - review: 照合の結果。
    ///   - rows: 一覧の行。
    /// - Returns: 注記。該当しなければ `nil`。
    private func outsideDataNotice(review: SessionRoadRegulationReview, rows: [SessionRoadRegulationReviewRow]) -> SessionRoadRegulationReviewNotice? {
        let hasOutsideRow = rows.contains { $0.undeterminedReason == .outsideRegulationData }
        return review.datasets.isEmpty || hasOutsideRow ? .outsideData : nil
    }
}
