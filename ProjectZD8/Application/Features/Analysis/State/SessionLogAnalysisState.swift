import Foundation

/// 保存済みセッションのPID時系列解析を画面へ公開する状態です。
struct SessionLogAnalysisState: Equatable {
    /// 解析読込の現在段階です。
    enum Phase: Equatable {
        /// セッション選択前または表示を閉じた状態です。
        case idle
        /// iCloudからRawログを取得するユーザー確認を待っています。
        case awaitingDownloadConfirmation
        /// iCloudからRawログを取得しています。
        case downloading
        /// RawログとPID定義を読込中です。
        case loading
        /// 時系列サンプルの生成が完了した状態です。
        case loaded
        /// 保存先または定義を読めなかった状態です。
        case failed
    }

    /// iCloud Rawログ取得前に表示する確認情報です。
    struct DownloadPrompt: Equatable {
        /// 取得対象のセッションIDです。
        let sessionID: ConnectionSessionID
        /// iCloudから取得するRaw Payloadの予定バイト数です。
        let byteCount: Int64

        /// 取得対象と予定容量を固定して確認情報を生成します。
        ///
        /// 責務: 1件のセッションIDと予定バイト数をRaw取得確認情報へ固定します。
        /// - Parameters:
        ///   - sessionID: 取得対象のセッションID。
        ///   - byteCount: iCloudから取得するRaw Payloadの予定バイト数。
        init(sessionID: ConnectionSessionID, byteCount: Int64) {
            self.sessionID = sessionID
            self.byteCount = byteCount
        }
    }

    /// 1件の時系列PID表示値です。
    struct TimelineSample: Identifiable, Equatable, Sendable {
        /// セッション内のRawログ順序です。
        let sequence: Int64
        /// 応答を観測した実時間です。
        let observedAt: Date
        /// OBD Service番号です。
        let service: UInt8
        /// Service内PID番号です。
        let pid: UInt8
        /// PID定義が提供する表示名キーです。
        let nameKey: String?
        /// 数式変換後の数値です。変換できない場合は `nil` です。
        let value: Double?
        /// 数値の単位です。
        let unit: String?
        /// 車種専用PIDの場合に表示する型式です。
        let vehicleModelCode: String?
        /// 数式を適用する前の応答データです。
        let payload: [UInt8]
        /// 数値化できなかった理由です。
        let decodingFailure: DecodingFailure?

        /// SwiftUIの行識別子です。
        var id: Int64 { sequence }

        /// 数値化不能なPIDの理由です。
        enum DecodingFailure: Equatable, Sendable {
            /// 保存済み定義がありません。
            case missingDefinition
            /// 定義はありますが式が確認されていません。
            case unavailableFormula
            /// Payload長または数式評価が定義を満たしません。
            case invalidPayload
        }

        /// 解析済みPID値を生成します。
        ///
        /// 責務: 1件のRaw PID応答を表示に必要な変換結果と来歴へ固定します。
        /// - Parameters:
        ///   - sequence: セッション内の記録順序。
        ///   - observedAt: 応答観測時刻。
        ///   - service: OBD Service番号。
        ///   - pid: Service内PID番号。
        ///   - nameKey: PID表示名キー。
        ///   - value: 数式変換後の値。
        ///   - unit: 数値単位。
        ///   - vehicleModelCode: 車種専用PIDの適用型式。
        ///   - payload: 元の応答データ。
        ///   - decodingFailure: 数値化不能理由。
        init(sequence: Int64, observedAt: Date, service: UInt8, pid: UInt8, nameKey: String?, value: Double?, unit: String?, vehicleModelCode: String? = nil, payload: [UInt8], decodingFailure: DecodingFailure?) {
            self.sequence = sequence
            self.observedAt = observedAt
            self.service = service
            self.pid = pid
            self.nameKey = nameKey
            self.value = value
            self.unit = unit
            self.vehicleModelCode = vehicleModelCode
            self.payload = payload
            self.decodingFailure = decodingFailure
        }
    }

    /// 現在の解析段階です。
    var phase: Phase = .idle
    /// 現在表示しているセッションIDです。
    var sessionID: ConnectionSessionID?
    /// ユーザー確認待ちのiCloud取得情報です。
    var downloadPrompt: DownloadPrompt?
    /// iCloud Asset取得率です。取得前は `nil` です。
    var downloadProgress: Double?
    /// セッション内の取得順序で昇順にしたPID時系列です。
    var timeline: [TimelineSample] = []
    /// 数式変換を完了した時系列サンプル件数です。
    var decodedSampleCount = 0
    /// 読込済みRawログの総件数です。Rawログ読込前は `nil` です。
    var totalSampleCount: Int?
    /// 数式変換できずRawのまま保持するサンプル件数です。
    var rawOnlySampleCount: Int { timeline.count - decodedSampleCount }
    /// 数値化済みサンプルをService/PID単位へまとめた折れ線系列です。
    var pidSeries: [SessionPIDSeries] = []
    /// 速度・回転数の滞在傾向と車速積算距離をまとめた走行サマリーです。
    var performanceSummary: SessionPerformanceSummary = .empty
    /// 取得できたPIDを車両部品・系統の観察目的へ結び付けた表示状態です。
    var componentInsights: [SessionComponentInsight] = []
    /// 近接時刻で対応付けられる代表PID組の散布図状態です。
    var relationships: [SessionPIDRelationship] = []
    /// 保存元または変換定義の読込失敗を示すキーです。
    var failureKey: String?
}
