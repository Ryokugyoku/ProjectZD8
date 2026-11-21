import Foundation

/// 交通規制データの ZIP を読み、CSV を1行ずつ解釈して渡す能力です。
///
/// 同期です。呼び出し元が `@concurrent` の文脈で呼びます。
nonisolated protocol RoadRegulationArchiveReaderPort: Sendable {
    /// ZIP を読みます。
    ///
    /// 責務: ZIP の中の CSV を先頭から読み、各行の解釈結果を `consume` へ順に渡します。
    /// - Parameters:
    ///   - url: 読む ZIP。
    ///   - progress: 読み取りの進み具合の通知。
    ///   - consume: 1行の解釈結果を受け取る処理。投げたエラーはそのまま伝えます。
    /// - Returns: 読み終えた時に分かる情報。
    /// - Throws: 形式の失敗は `RoadRegulationImportError.archiveInvalid` / `.csvFormatChanged`、ほかは `consume` が投げたエラー。
    func read(
        archiveAt url: URL,
        progress: (RoadRegulationArchiveReadProgress) -> Void,
        consume: (RoadRegulationArchiveRecord) throws -> Void
    ) throws -> RoadRegulationArchiveSummary
}
