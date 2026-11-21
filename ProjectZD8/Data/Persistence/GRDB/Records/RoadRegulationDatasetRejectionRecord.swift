import Foundation
import GRDB

/// GRDBへ保存する、交通規制データの版ごとの拒否件数の永続化表現です。
nonisolated struct RoadRegulationDatasetRejectionRecord: Codable, FetchableRecord, PersistableRecord {
    /// 拒否件数の表名です。
    static let databaseTableName = "road_regulation_dataset_rejections"

    /// 版のUUIDの小文字の文字列表現です。
    let datasetID: String
    /// 拒否理由の rawValue です。
    let reason: String
    /// 拒否した行数です。
    let count: Int64

    /// 版と拒否理由と件数から生成します。
    ///
    /// 責務: 1件の拒否件数を列指向の永続化表現へ変換します。
    /// - Parameters:
    ///   - datasetID: 所属する版。
    ///   - reason: 拒否理由。
    ///   - count: 拒否した行数。
    init(datasetID: RoadRegulationDatasetID, reason: RoadRegulationRowRejection, count: Int) {
        self.datasetID = datasetID.rawValue.uuidString.lowercased()
        self.reason = reason.rawValue
        self.count = Int64(count)
    }

    /// 拒否件数の一覧を、件数が正の理由だけの行にします。
    ///
    /// 責務: 0件の理由を除き、理由の rawValue の昇順で行を作ります。負の件数は表の CHECK で拒否させます。
    /// - Parameters:
    ///   - rejectedByReason: 理由ごとの件数。
    ///   - datasetID: 所属する版。
    /// - Returns: 保存する行。
    static func records(
        for rejectedByReason: [RoadRegulationRowRejection: Int],
        datasetID: RoadRegulationDatasetID
    ) -> [RoadRegulationDatasetRejectionRecord] {
        rejectedByReason
            .filter { $0.value != 0 }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { RoadRegulationDatasetRejectionRecord(datasetID: datasetID, reason: $0.key, count: $0.value) }
    }

    /// 保存済みの行の一覧を理由ごとの件数へ復元します。
    ///
    /// 責務: 既知の理由と、Int で表せる正の件数だけを受け付けます。
    /// - Parameter records: 1つの版の拒否件数の行。
    /// - Returns: 理由ごとの件数。
    /// - Throws: 未知の理由・範囲外の件数・理由の重複は `RoadRegulationRepositoryError.integrityConflict`。
    static func rejectedByReason(
        from records: [RoadRegulationDatasetRejectionRecord]
    ) throws -> [RoadRegulationRowRejection: Int] {
        var result: [RoadRegulationRowRejection: Int] = [:]
        for record in records {
            guard let reason = RoadRegulationRowRejection(rawValue: record.reason),
                  let count = Int(exactly: record.count), count > 0,
                  result[reason] == nil else {
                throw RoadRegulationRepositoryError.integrityConflict
            }
            result[reason] = count
        }
        return result
    }
}
