import Foundation
import GRDB

/// GRDBへ保存する、交通規制1件の永続化表現です。
nonisolated struct RoadRegulationRecord: Codable, FetchableRecord, PersistableRecord {
    /// 規制の表名です。
    static let databaseTableName = "road_regulations"

    /// 行 ID です。挿入前は nil。
    let id: Int64?
    /// 所属する版のUUIDの小文字の文字列表現です。
    let datasetID: String
    /// 配布データのユニークキーです。
    let uniqueKey: String
    /// 種別の rawValue です。
    let kind: String
    /// 最高速度(km/h)です。
    let speedLimitKph: Int64?
    /// 片側・両側コードです。
    let sideCode: Int64?
    /// 指定・禁止方向の別コードです。
    let oneWayOrder: Int64?
    /// 面規制の外周道路を含むかどうかです。
    let perimeterRoadIncluded: Bool?
    /// 条件の JSON(キーを並べ替える)です。条件なしは nil。
    let conditions: String?
    /// 形状の BLOB です。
    let geometry: Data

    /// 保存前の規制から挿入用の行を作ります。
    ///
    /// 責務: 条件を JSON の文字列(条件なしは nil)へ、形状を BLOB へ変換します。
    /// - Parameters:
    ///   - draft: 保存前の規制。
    ///   - datasetID: 所属する版。
    ///   - codec: 形状の符号化。
    /// - Throws: 条件を JSON にできない場合は `RoadRegulationRepositoryError.integrityConflict`。
    init(draft: RoadRegulationDraft, datasetID: RoadRegulationDatasetID, codec: RoadRegulationGeometryBlobCodec) throws {
        id = nil
        self.datasetID = datasetID.rawValue.uuidString.lowercased()
        uniqueKey = draft.uniqueKey
        kind = draft.kind.rawValue
        speedLimitKph = draft.speedLimitKph.map(Int64.init)
        sideCode = draft.side.map { Int64($0.rawValue) }
        oneWayOrder = draft.oneWayOrder.map { Int64($0.rawValue) }
        perimeterRoadIncluded = draft.perimeterRoadIncluded
        conditions = try Self.encodedConditions(draft.conditions)
        geometry = codec.encode(draft.geometry)
    }

    /// 挿入の文に渡す引数です(id を除く列の順)。
    var insertionArguments: StatementArguments {
        [datasetID, uniqueKey, kind, speedLimitKph, sideCode, oneWayOrder, perimeterRoadIncluded, conditions, geometry]
    }

    /// 保存済みの行を Domain の規制へ復元します。
    ///
    /// 責務: 識別子・種別・コード・条件・形状を検証して復元します。
    /// - Parameter codec: 形状の復号。
    /// - Returns: 復元した規制。
    /// - Throws: 復元できない値は `RoadRegulationRepositoryError.integrityConflict`。
    func makeDomainRegulation(codec: RoadRegulationGeometryBlobCodec) throws -> RoadRegulation {
        guard let id, let uuid = UUID(uuidString: datasetID), let kind = RoadRegulationKind(rawValue: kind) else {
            throw RoadRegulationRepositoryError.integrityConflict
        }
        return RoadRegulation(
            id: RoadRegulationID(rawValue: id),
            datasetID: RoadRegulationDatasetID(rawValue: uuid),
            uniqueKey: uniqueKey,
            kind: kind,
            speedLimitKph: try speedLimitKph.map(Self.integer),
            side: try sideCode.map { try Self.code($0, RoadRegulationSideCode.init) },
            oneWayOrder: try oneWayOrder.map { try Self.code($0, RoadRegulationOneWayOrder.init) },
            perimeterRoadIncluded: perimeterRoadIncluded,
            conditions: try Self.decodedConditions(conditions),
            geometry: try codec.decode(geometry)
        )
    }

    /// 条件を JSON の文字列にします。
    ///
    /// 責務: 条件なしは nil、それ以外はキーを並べ替えた JSON にします。
    /// - Parameter conditions: 条件。
    /// - Returns: JSON の文字列、または nil。
    /// - Throws: 符号化に失敗した場合は `RoadRegulationRepositoryError.integrityConflict`。
    private static func encodedConditions(_ conditions: RoadRegulationConditions) throws -> String? {
        guard !conditions.isUnconditional else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(conditions), let text = String(data: data, encoding: .utf8) else {
            throw RoadRegulationRepositoryError.integrityConflict
        }
        return text
    }

    /// JSON の文字列から条件を復元します。
    ///
    /// 責務: nil は条件なし、それ以外は JSON として復号します。
    /// - Parameter text: 保存済みの JSON。
    /// - Returns: 条件。
    /// - Throws: 復号に失敗した場合は `RoadRegulationRepositoryError.integrityConflict`。
    private static func decodedConditions(_ text: String?) throws -> RoadRegulationConditions {
        guard let text else { return .unconditional }
        guard let decoded = try? JSONDecoder().decode(RoadRegulationConditions.self, from: Data(text.utf8)) else {
            throw RoadRegulationRepositoryError.integrityConflict
        }
        return decoded
    }

    /// Int64 を Int へ変換します。
    ///
    /// 責務: Int で表せない値を整合性エラーにします。
    /// - Parameter value: 保存済みの値。
    /// - Returns: 変換した値。
    /// - Throws: 範囲外は `RoadRegulationRepositoryError.integrityConflict`。
    private static func integer(_ value: Int64) throws -> Int {
        guard let converted = Int(exactly: value) else { throw RoadRegulationRepositoryError.integrityConflict }
        return converted
    }

    /// 保存済みのコードを列挙型へ変換します。
    ///
    /// 責務: 未知のコードを整合性エラーにします。
    /// - Parameters:
    ///   - value: 保存済みのコード。
    ///   - make: rawValue から列挙型を作る処理。
    /// - Returns: 変換した値。
    /// - Throws: 未知のコードは `RoadRegulationRepositoryError.integrityConflict`。
    private static func code<Code>(_ value: Int64, _ make: (Int) -> Code?) throws -> Code {
        guard let converted = make(try integer(value)) else { throw RoadRegulationRepositoryError.integrityConflict }
        return converted
    }
}
