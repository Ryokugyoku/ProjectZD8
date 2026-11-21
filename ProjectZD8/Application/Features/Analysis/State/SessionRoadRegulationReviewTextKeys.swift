import Foundation

/// 交通規制の照合の表示に使うローカライズキー・SF Symbols の名前・色の分類を表から引きます。
///
/// 判定の結果に文言は持たせず、ここで種類と分類からキーを決めます。断定を避けるため `.tone(.critical)` は返しません。
nonisolated struct SessionRoadRegulationReviewTextKeys: Sendable {
    /// 解析画面の照合のキーの共通の接頭辞です。
    private static let prefix = "analysis.road_regulation"
    /// 規制の判定のキーの共通の接頭辞です。
    private static let verdictPrefix = "road_regulation.verdict"
    /// 表に無い組み合わせと判定できない時に使うラベルのキーです。
    private static let undeterminedLabelKey = "analysis.road_regulation.outcome.undetermined"
    /// 分類と種類ごとのラベルのキーの表です(判定できない分類は表に持たず、既定のキーに倒します)。
    private static let labelTable: [SessionRoadRegulationReviewOutcome: [SessionRoadRegulationReviewKind: String]] = [
        .possibleIssue: [
            .speedLimit: "\(verdictPrefix).speed_limit.exceeded",
            .stop: "\(verdictPrefix).stop.not_stopped",
            .oneWay: "\(verdictPrefix).one_way.possible_wrong_way",
        ],
        .compliant: [
            .speedLimit: "\(verdictPrefix).speed_limit.within_limit",
            .stop: "\(verdictPrefix).stop.stopped",
            .oneWay: "\(verdictPrefix).one_way.followed_direction",
        ],
        .observedOnly: [.slowDown: "\(verdictPrefix).slow_down.observed"],
        .unregulated: [.speedLimit: "\(verdictPrefix).speed_limit.unregulated"],
    ]

    /// 状態を持たない表引きを作ります。
    ///
    /// 責務: 定数だけでキーを決める表引きを用意します。
    init() {}

    /// 凡例の「該当する規制なし」のキーです。
    var notApplicableLabelKey: String { "\(Self.prefix).legend.not_applicable" }
    /// 種類の通過が0件の時の一覧の文言のキーです。
    var emptyKindKey: String { "\(Self.prefix).list.empty_kind" }
    /// 絞り込みで行が0件になった時の一覧の文言のキーです。
    var emptyFilteredKey: String { "\(Self.prefix).list.empty_attention" }

    /// 規制の種類名のキーを返します。
    ///
    /// 責務: 種類を `road_regulation.kind.<snake_case>` のキーへ写します。
    /// - Parameter kind: 規制の種類。
    /// - Returns: ローカライズキー。
    func kindTitleKey(for kind: SessionRoadRegulationReviewKind) -> String {
        "road_regulation.kind.\(Self.snakeName(of: kind))"
    }

    /// 種類ごとの重ね合わせの ID を返します。
    ///
    /// 責務: 種類を `road_regulation.<snake_case>` の ID へ写します(種類ごとに異なる値)。
    /// - Parameter kind: 規制の種類。
    /// - Returns: 重ね合わせの ID。
    func overlayID(for kind: SessionRoadRegulationReviewKind) -> String {
        "road_regulation.\(Self.snakeName(of: kind))"
    }

    /// 種類ごとの重ね合わせの名前のキーを返します。
    ///
    /// 責務: 種類を `analysis.road_regulation.overlay.<snake_case>` のキーへ写します。
    /// - Parameter kind: 規制の種類。
    /// - Returns: ローカライズキー。
    func overlayTitleKey(for kind: SessionRoadRegulationReviewKind) -> String {
        "\(Self.prefix).overlay.\(Self.snakeName(of: kind))"
    }

    /// まとめと凡例に使う、種類と分類のラベルのキーを返します。
    ///
    /// 責務: 表にある組み合わせはその判定のキーを、表に無い組み合わせと判定できない分類は「判定できない」のキーを返します。
    /// - Parameters:
    ///   - kind: 規制の種類。
    ///   - outcome: 判定の分類。
    /// - Returns: ローカライズキー。
    func outcomeLabelKey(kind: SessionRoadRegulationReviewKind, outcome: SessionRoadRegulationReviewOutcome) -> String {
        Self.labelTable[outcome]?[kind] ?? Self.undeterminedLabelKey
    }

    /// 分類の色の分類を返します。
    ///
    /// 責務: 分類を重ね合わせの色調へ写します(重大さの色調は使いません)。
    /// - Parameter outcome: 判定の分類。
    /// - Returns: 色の分類。
    func category(for outcome: SessionRoadRegulationReviewOutcome) -> RouteAnalysisColorCategory {
        switch outcome {
        case .possibleIssue: .tone(.caution)
        case .undeterminable: .tone(.unknown)
        case .compliant: .tone(.positive)
        case .observedOnly, .unregulated: .tone(.neutral)
        }
    }

    /// 分類の行に添える SF Symbols の名前を返します。
    ///
    /// 責務: 分類を記号の名前へ写します。
    /// - Parameter outcome: 判定の分類。
    /// - Returns: SF Symbols の名前。
    func systemImage(for outcome: SessionRoadRegulationReviewOutcome) -> String {
        switch outcome {
        case .possibleIssue: "exclamationmark.triangle.fill"
        case .undeterminable: "questionmark.circle"
        case .compliant: "checkmark.circle"
        case .observedOnly: "gauge.with.dots.needle.33percent"
        case .unregulated: "minus.circle"
        }
    }

    /// 照合の段階の文言のキーを返します。
    ///
    /// 責務: 結果を出した段階は `nil`、それ以外は段階ごとの文言のキーを返します。
    /// - Parameter status: 照合の段階。
    /// - Returns: ローカライズキー。結果を出した段階では `nil`。
    func statusMessageKey(for status: SessionRoadRegulationReviewStatus) -> String? {
        switch status {
        case .idle, .waitingForRoute: "\(Self.prefix).status.waiting_for_route"
        case .routeUnavailable: "\(Self.prefix).status.route_unavailable"
        case .waitingForRawLog: "\(Self.prefix).status.waiting_for_raw_log"
        case .evaluating: "\(Self.prefix).status.evaluating"
        case .loaded: nil
        case .noTrack: "\(Self.prefix).status.no_track"
        case .noRegulationData: "\(Self.prefix).status.no_regulation_data"
        case .failed: "\(Self.prefix).status.failed"
        }
    }

    /// 照合の段階に添える SF Symbols の名前を返します。
    ///
    /// 責務: 進み具合を示す段階と結果を出した段階は `nil`、それ以外は段階ごとの記号の名前を返します。
    /// - Parameter status: 照合の段階。
    /// - Returns: SF Symbols の名前。進み具合を示す段階と結果を出した段階では `nil`。
    func statusSystemImage(for status: SessionRoadRegulationReviewStatus) -> String? {
        switch status {
        case .idle, .waitingForRoute: "hourglass"
        case .routeUnavailable: "map"
        case .waitingForRawLog, .evaluating, .loaded: nil
        case .noTrack: "location.slash"
        case .noRegulationData: "square.and.arrow.down"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    /// 種類のキーに使う snake_case の名前を返します。
    ///
    /// 責務: 種類を `speed_limit` などの名前へ写します。
    /// - Parameter kind: 規制の種類。
    /// - Returns: snake_case の名前。
    private static func snakeName(of kind: SessionRoadRegulationReviewKind) -> String {
        switch kind {
        case .speedLimit: "speed_limit"
        case .stop: "stop"
        case .oneWay: "one_way"
        case .slowDown: "slow_down"
        }
    }
}
