import Foundation

/// HOME接続開始から通信終了までの1回の接続履歴です。
nonisolated struct ConnectionSession: Identifiable, Equatable, Codable, Sendable {
    /// 履歴画面が表示するセッション状態です。
    enum Status: Equatable, Sendable {
        /// 現在も接続と取得が継続しています。
        case connected
        /// ユーザー操作によって正常に終了しました。
        case completed
        /// 通信または処理上の理由で中断しました。
        case interrupted
    }

    /// セッションの安定識別子です。
    let id: ConnectionSessionID
    /// セッションを所有するAppleアカウント識別子です。
    let accountIdentifier: String
    /// HOMEで接続開始を押した日時です。
    let startedAt: Date
    /// 終了が確定した日時です。
    var endedAt: Date?
    /// 終了が確定した直接原因です。
    var endReason: ConnectionSessionEndReason?
    /// 自動判別できない終了に対するユーザー確認結果です。
    var stopReviewDecision: ConnectionSessionStopReviewDecision?
    /// 接続時点の登録車両表示情報です。
    var vehicle: ConnectionSessionVehicle?
    /// 車両未確定のまま記録したセッションが観測したVINです。
    ///
    /// 前後の空白を除いた非空文字列か `nil` だけを保持します。代入値は同じ規則で正規化します。
    /// このキーを持たない旧CloudKitメタデータは `nil` として復号します。
    var observedVIN: String? {
        didSet {
            let normalized = Self.normalizedObservedVIN(observedVIN)
            if normalized != observedVIN {
                observedVIN = normalized
            }
        }
    }
    /// ログ取得を開始した端末の表示情報です。
    var acquisitionDevice: ConnectionSessionAcquisitionDevice?
    /// セッション内で最初に取得できた累積走行距離です。
    var startingOdometerKilometers: Double?
    /// セッション内で最後に取得できた累積走行距離です。
    var endingOdometerKilometers: Double?
    /// 累積走行距離を車種専用PIDから取得した場合の型式です。
    var distanceSourceModelCode: String?
    /// 未デコードRawログの件数と端末間保管状態です。
    var rawLogSummary: ConnectionSessionRawLogSummary

    /// 終了情報から履歴表示用の現在状態を返します。
    var status: Status {
        guard let endReason else { return .connected }
        return endReason == .userDisconnected || stopReviewDecision == .userInitiated
            ? .completed
            : .interrupted
    }

    /// ユーザー操作の可能性があるため確認を提示できる終了かを示します。
    var needsStopReview: Bool {
        guard stopReviewDecision == nil else { return false }
        return endReason == .vehicleNoResponse || endReason == .connectionLost
    }

    /// セッション中の累積走行距離差分です。
    var recordedDistanceKilometers: Double? {
        guard let startingOdometerKilometers, let endingOdometerKilometers,
              startingOdometerKilometers.isFinite, endingOdometerKilometers.isFinite,
              startingOdometerKilometers >= 0, endingOdometerKilometers >= startingOdometerKilometers else {
            return nil
        }
        return endingOdometerKilometers - startingOdometerKilometers
    }

    /// セッションの所有者と開始時刻を固定して生成します。
    ///
    /// 責務: 1回のHOME接続開始を未終了の接続セッションへ変換します。
    /// - Parameters:
    ///   - id: セッションへ割り当てる安定識別子。
    ///   - accountIdentifier: セッションを所有するAppleアカウント識別子。
    ///   - startedAt: HOMEで接続開始を押した日時。
    ///   - vehicle: 開始時点で確定済みの場合に保持する車両情報。
    ///   - acquisitionDevice: ログ取得を開始した端末の表示情報。
    ///   - observedVIN: 車両未確定のまま観測したVIN。前後の空白を除き、空なら `nil` として保持します。
    init(
        id: ConnectionSessionID = ConnectionSessionID(),
        accountIdentifier: String,
        startedAt: Date = Date(),
        vehicle: ConnectionSessionVehicle? = nil,
        acquisitionDevice: ConnectionSessionAcquisitionDevice? = nil,
        observedVIN: String? = nil
    ) {
        self.id = id
        self.accountIdentifier = accountIdentifier
        self.startedAt = startedAt
        endedAt = nil
        endReason = nil
        stopReviewDecision = nil
        self.vehicle = vehicle
        self.observedVIN = Self.normalizedObservedVIN(observedVIN)
        self.acquisitionDevice = acquisitionDevice
        startingOdometerKilometers = nil
        endingOdometerKilometers = nil
        distanceSourceModelCode = nil
        rawLogSummary = .empty
    }

    /// 符号化キーです。合成Codableと同じキー名を明示し、既存の符号化形式を維持します。
    private enum CodingKeys: String, CodingKey {
        /// セッションの安定識別子のキーです。
        case id
        /// 所有するAppleアカウント識別子のキーです。
        case accountIdentifier
        /// 接続開始日時のキーです。
        case startedAt
        /// 終了確定日時のキーです。
        case endedAt
        /// 終了原因のキーです。
        case endReason
        /// 終了に対するユーザー確認結果のキーです。
        case stopReviewDecision
        /// 接続時点の登録車両表示情報のキーです。
        case vehicle
        /// 車両未割当のまま観測したVINのキーです。旧データには存在しません。
        case observedVIN
        /// ログ取得端末の表示情報のキーです。
        case acquisitionDevice
        /// 最初に取得した累積走行距離のキーです。
        case startingOdometerKilometers
        /// 最後に取得した累積走行距離のキーです。
        case endingOdometerKilometers
        /// 累積走行距離の取得元型式のキーです。
        case distanceSourceModelCode
        /// 未デコードRawログの件数と保管状態のキーです。
        case rawLogSummary
    }

    /// 符号化済みセッションを復号し、観測VINを正規化します。
    ///
    /// 責務: 合成Codableと同じキーで復号し、観測VINだけを初期化子と同じ規則で正規化します。
    /// - Parameter decoder: 復号元のdecoder。`observedVIN` キーが無い旧データは `nil` として扱います。
    /// - Throws: 必須キー欠落または値の型不一致の場合の `DecodingError`。
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ConnectionSessionID.self, forKey: .id)
        accountIdentifier = try container.decode(String.self, forKey: .accountIdentifier)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        endReason = try container.decodeIfPresent(ConnectionSessionEndReason.self, forKey: .endReason)
        stopReviewDecision = try container.decodeIfPresent(ConnectionSessionStopReviewDecision.self, forKey: .stopReviewDecision)
        vehicle = try container.decodeIfPresent(ConnectionSessionVehicle.self, forKey: .vehicle)
        observedVIN = Self.normalizedObservedVIN(try container.decodeIfPresent(String.self, forKey: .observedVIN))
        acquisitionDevice = try container.decodeIfPresent(ConnectionSessionAcquisitionDevice.self, forKey: .acquisitionDevice)
        startingOdometerKilometers = try container.decodeIfPresent(Double.self, forKey: .startingOdometerKilometers)
        endingOdometerKilometers = try container.decodeIfPresent(Double.self, forKey: .endingOdometerKilometers)
        distanceSourceModelCode = try container.decodeIfPresent(String.self, forKey: .distanceSourceModelCode)
        rawLogSummary = try container.decode(ConnectionSessionRawLogSummary.self, forKey: .rawLogSummary)
    }

    /// 観測VINを保存可能な正規形へ変換します。
    ///
    /// 責務: 任意のVIN文字列を前後の空白を除いた非空文字列か `nil` へ変換します。
    ///
    /// 除く文字は `CharacterSet.whitespacesAndNewlines` 全体です。DBのCHECKが拒否するのはそのうち
    /// 半角スペース、タブ、LF、CR、垂直タブ、改ページだけで、NBSP・NEL・U+2028・全角スペース等はこの正規化だけで除きます。
    /// - Parameter vin: 正規化する観測VIN。
    /// - Returns: 前後の空白と改行を除いた非空文字列。入力が `nil` または空白だけの場合は `nil`。
    static func normalizedObservedVIN(_ vin: String?) -> String? {
        guard let trimmed = vin?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
