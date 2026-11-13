/// セッション開始時点で固定した、1つのPIDの取得条件と変換規則です。
///
/// 後からPID定義を改訂しても、取得時の規則でRawを再解釈できるようにセッションごとに複写します。
nonisolated struct SessionPID: Equatable, Codable, Sendable {
    /// セッション内での並び順です(0始まり、欠番なし)。
    let ordinal: Int
    let request: OBDPIDRequest
    /// 車種専用PIDの送信先CANヘッダーです。
    let header: UInt16?
    let support: PIDSupport
    /// このセッションで収集対象にしたかどうかです。
    let isCollectionEnabled: Bool
    /// 毎ティック取得する高頻度グループかどうかです。
    let isFastGroup: Bool
    /// 複写元のPID定義の改訂番号です。
    let definitionRevision: Int
    let requiredByteCount: Int?
    let formula: String?
    let unit: String
    let minimumValue: Double?
    let maximumValue: Double?

    /// セッションPIDを生成します。
    ///
    /// 責務: 1件のPIDの取得条件と変換規則をセッション用に固定します。
    init(
        ordinal: Int,
        request: OBDPIDRequest,
        header: UInt16?,
        support: PIDSupport,
        isCollectionEnabled: Bool,
        isFastGroup: Bool,
        definitionRevision: Int,
        requiredByteCount: Int?,
        formula: String?,
        unit: String,
        minimumValue: Double?,
        maximumValue: Double?
    ) {
        self.ordinal = ordinal
        self.request = request
        self.header = header
        self.support = support
        self.isCollectionEnabled = isCollectionEnabled
        self.isFastGroup = isFastGroup
        self.definitionRevision = definitionRevision
        self.requiredByteCount = requiredByteCount
        self.formula = formula
        self.unit = unit
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
    }

    /// 取得対象として実際に要求するPIDかどうかです。
    var isPolled: Bool { support == .supported && isCollectionEnabled }
}
