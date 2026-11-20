import Foundation
import GRDB

/// GRDBへ保存する、交通規制データの版の永続化表現です。
nonisolated struct RoadRegulationDatasetRecord: Codable, FetchableRecord, PersistableRecord {
    /// 版の表名です。
    static let databaseTableName = "road_regulation_datasets"

    /// 版のUUIDの小文字の文字列表現です。
    let id: String
    /// 都道府県コード(1...47)です。
    let prefectureCode: Int64
    /// 版の状態の rawValue です。
    var state: String
    /// 配布の公開日時の印("yyyyMMddHHmm" の12文字)です。
    let publicationStamp: String
    /// 取得元のURLの文字列です。
    let sourceURL: String
    /// 取得した時刻のmicrosecondです。
    let downloadedAtMicroseconds: Int64
    /// 有効にした時刻のmicrosecondです。有効にするまで nil。
    var activatedAtMicroseconds: Int64?
    /// データの年です。有効にするまで nil。
    var dataYear: Int64?
    /// データの月です。有効にするまで nil。
    var dataMonth: Int64?
    /// CSV の形式の版です。有効にするまで nil。
    var formatVersion: String?
    /// 読んだ行数です。
    var totalRowCount: Int64
    /// 取り込んだ規制の件数です。
    var importedCount: Int64
    /// 対象外の種別として読み飛ばした行数です。
    var skippedOutOfScopeCount: Int64
    /// 廃止済みとして読み飛ばした行数です。
    var skippedAbolishedCount: Int64
    /// 収録範囲の最小緯度です。
    var coverageMinLatitude: Double?
    /// 収録範囲の最大緯度です。
    var coverageMaxLatitude: Double?
    /// 収録範囲の最小経度です。
    var coverageMinLongitude: Double?
    /// 収録範囲の最大経度です。
    var coverageMaxLongitude: Double?

    /// 取り込み前の版の情報から、取り込み中の版の行を作ります。
    ///
    /// 責務: 新しい識別子と `importing` の状態で、結果の欄が空の行を作ります。
    /// - Parameters:
    ///   - id: 新しい版の識別子。
    ///   - draft: 取り込み前に分かっている版の情報。
    /// - Throws: 取得時刻を Int64 の microsecond で表せない場合は `ConnectionSessionRepositoryError.integrityConflict`。
    init(id: RoadRegulationDatasetID, draft: RoadRegulationDatasetDraft) throws {
        self.id = id.rawValue.uuidString.lowercased()
        prefectureCode = Int64(draft.prefecture.rawValue)
        state = RoadRegulationDatasetState.importing.rawValue
        publicationStamp = draft.publicationStamp
        sourceURL = draft.sourceURL.absoluteString
        downloadedAtMicroseconds = try ConnectionSessionMicrosecondTimestamp.microseconds(for: draft.downloadedAt)
        totalRowCount = 0
        importedCount = 0
        skippedOutOfScopeCount = 0
        skippedAbolishedCount = 0
    }

    /// 取り込みの結果を書き込み、有効な状態にした行を返します。
    ///
    /// 責務: 結果の欄と有効にした時刻を埋め、状態を `active` にします。値の範囲は表の CHECK で守ります。
    /// - Parameters:
    ///   - summary: 取り込みの結果。
    ///   - activatedAt: 有効にした時刻。
    /// - Returns: 有効にした行。
    /// - Throws: 時刻を Int64 の microsecond で表せない場合は `ConnectionSessionRepositoryError.integrityConflict`。
    func activated(with summary: RoadRegulationImportSummary, at activatedAt: Date) throws -> RoadRegulationDatasetRecord {
        var record = self
        record.state = RoadRegulationDatasetState.active.rawValue
        record.activatedAtMicroseconds = try ConnectionSessionMicrosecondTimestamp.microseconds(for: activatedAt)
        record.dataYear = Int64(summary.dataMonth.year)
        record.dataMonth = Int64(summary.dataMonth.month)
        record.formatVersion = summary.formatVersion
        record.totalRowCount = Int64(summary.counts.totalRows)
        record.importedCount = Int64(summary.counts.importedRegulations)
        record.skippedOutOfScopeCount = Int64(summary.counts.skippedOutOfScope)
        record.skippedAbolishedCount = Int64(summary.counts.skippedAbolished)
        record.coverageMinLatitude = summary.coverage.minLatitude
        record.coverageMaxLatitude = summary.coverage.maxLatitude
        record.coverageMinLongitude = summary.coverage.minLongitude
        record.coverageMaxLongitude = summary.coverage.maxLongitude
        return record
    }

    /// 保存済みの行を Domain の版へ復元します。
    ///
    /// 責務: 識別子・県・状態・年月・URL・件数・収録範囲を検証して復元します。有効にした時刻などが空の行は復元しません。
    /// - Parameter rejections: この版の拒否件数の行。
    /// - Returns: 復元した版。
    /// - Throws: 復元できない値は `RoadRegulationRepositoryError.integrityConflict`。
    func makeDomainDataset(rejections: [RoadRegulationDatasetRejectionRecord]) throws -> RoadRegulationDataset {
        guard let uuid = UUID(uuidString: id),
              let prefecture = Int(exactly: prefectureCode).flatMap(JapanesePrefectureCode.init),
              let state = RoadRegulationDatasetState(rawValue: state),
              let url = URL(string: sourceURL),
              let activatedAtMicroseconds, let formatVersion,
              let dataMonth = makeDataMonth(), let coverage = makeCoverage() else {
            throw RoadRegulationRepositoryError.integrityConflict
        }
        return RoadRegulationDataset(
            id: RoadRegulationDatasetID(rawValue: uuid),
            prefecture: prefecture,
            state: state,
            dataMonth: dataMonth,
            publicationStamp: publicationStamp,
            sourceURL: url,
            downloadedAt: ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: downloadedAtMicroseconds),
            activatedAt: ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: activatedAtMicroseconds),
            formatVersion: formatVersion,
            counts: try makeCounts(rejections: rejections),
            coverage: coverage
        )
    }

    /// 年と月の列からデータの年月を作ります。
    ///
    /// 責務: どちらかが空・範囲外なら nil を返します。
    /// - Returns: データの年月。
    private func makeDataMonth() -> RoadRegulationDataMonth? {
        guard let year = dataYear.flatMap({ Int(exactly: $0) }),
              let month = dataMonth.flatMap({ Int(exactly: $0) }) else { return nil }
        return RoadRegulationDataMonth(year: year, month: month)
    }

    /// 収録範囲の4列から矩形を作ります。
    ///
    /// 責務: どれかが空・範囲外・大小が逆なら nil を返します。
    /// - Returns: 収録範囲。
    private func makeCoverage() -> GeoBoundingBox? {
        guard let coverageMinLatitude, let coverageMaxLatitude, let coverageMinLongitude, let coverageMaxLongitude else {
            return nil
        }
        return GeoBoundingBox(
            minLatitude: coverageMinLatitude,
            maxLatitude: coverageMaxLatitude,
            minLongitude: coverageMinLongitude,
            maxLongitude: coverageMaxLongitude
        )
    }

    /// 件数の列と拒否件数の行から取り込みの件数を作ります。
    ///
    /// 責務: 各件数が Int で表せる0以上の値であることを確かめます。
    /// - Parameter rejections: この版の拒否件数の行。
    /// - Returns: 取り込みの件数。
    /// - Throws: 範囲外の件数・未知の拒否理由は `RoadRegulationRepositoryError.integrityConflict`。
    private func makeCounts(rejections: [RoadRegulationDatasetRejectionRecord]) throws -> RoadRegulationImportCounts {
        RoadRegulationImportCounts(
            totalRows: try Self.count(totalRowCount),
            importedRegulations: try Self.count(importedCount),
            skippedOutOfScope: try Self.count(skippedOutOfScopeCount),
            skippedAbolished: try Self.count(skippedAbolishedCount),
            rejectedByReason: try RoadRegulationDatasetRejectionRecord.rejectedByReason(from: rejections)
        )
    }

    /// 保存済みの件数を Int へ変換します。
    ///
    /// 責務: Int で表せない値と負の値を整合性エラーにします。
    /// - Parameter value: 保存済みの件数。
    /// - Returns: 件数。
    /// - Throws: 範囲外は `RoadRegulationRepositoryError.integrityConflict`。
    private static func count(_ value: Int64) throws -> Int {
        guard let converted = Int(exactly: value), converted >= 0 else {
            throw RoadRegulationRepositoryError.integrityConflict
        }
        return converted
    }
}
