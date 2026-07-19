import Foundation

/// OBD識別処理から得た1回分の改変しない車両観測結果です。
struct VehicleIdentificationSnapshot: Equatable, Codable, Sendable {
    /// VINとして取得された未加工文字列です。
    let vin: String?
    /// VINと確認できないOBD応答から取得した識別子です。
    let obdIdentifier: String?
    /// ECUなどから取得できた全表示可能フィールドです。
    let fields: [Field]
    /// 後続の未加工保存へ渡せるコマンド単位の原文応答です。
    let rawResponses: [RawResponse]
    /// 観測が完了した日時です。
    let observedAt: Date

    /// OBD識別結果に含まれる1件の名称付き観測値です。
    struct Field: Equatable, Codable, Identifiable, Sendable {
        /// 同一観測内で安定するフィールド識別子です。
        let id: String
        /// ユーザーへ表示できる項目名です。
        let label: String
        /// ECUから取得した未加工の表示値です。
        let value: String
        /// 値を返したECUまたは識別サービスです。
        let source: String

        /// 名称、値、取得元を持つ観測フィールドを生成します。
        ///
        /// 責務: 1件のOBD観測値を取得元付き表示フィールドとして固定します。
        /// - Parameters:
        ///   - id: フィールド識別子。
        ///   - label: 表示項目名。
        ///   - value: 未加工の表示値。
        ///   - source: 取得元。
        init(id: String, label: String, value: String, source: String) {
            self.id = id
            self.label = label
            self.value = value
            self.source = source
        }
    }

    /// 1件のOBD要求に対してアダプターから返された加工前文字列です。
    struct RawResponse: Equatable, Codable, Sendable {
        /// 実行した型付き要求の安定識別子です。
        let requestID: String
        /// アダプターが返したプロンプト終端前の原文です。
        let payload: String

        /// 要求識別子と原文応答を固定します。
        ///
        /// 責務: 1件のOBD要求と加工前応答を再解析可能な組として保持します。
        /// - Parameters:
        ///   - requestID: 型付き要求の安定識別子。
        ///   - payload: 改行や空白を保持した原文応答。
        init(requestID: String, payload: String) {
            self.requestID = requestID
            self.payload = payload
        }
    }

    /// 1回分の車両識別観測を生成します。
    ///
    /// 責務: VINまたは非VINのOBD識別子と全取得フィールドを同じ観測時点へ固定します。
    /// - Parameters:
    ///   - vin: VINとして取得された文字列。
    ///   - obdIdentifier: VINと確認できないOBD由来識別子。
    ///   - fields: 取得できた全表示可能フィールド。
    ///   - rawResponses: 要求単位の加工前応答。
    ///   - observedAt: 観測完了日時。
    init(
        vin: String?,
        obdIdentifier: String? = nil,
        fields: [Field],
        rawResponses: [RawResponse] = [],
        observedAt: Date
    ) {
        self.vin = vin
        self.obdIdentifier = obdIdentifier
        self.fields = fields
        self.rawResponses = rawResponses
        self.observedAt = observedAt
    }
}
