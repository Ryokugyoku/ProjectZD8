/// 軌跡の取得結果から、走行ルートの表示の状態(描くルート、または描けない理由)と注記のキーを決めます。
///
/// 描ける点が無い時は `route` を `nil` にして理由を返し、空の地図を出させません。
/// 以前に復元した写しを最新と確かめられなかった時は、理由を出す時も含めて注記の最後に「未確認の復元」を足します。
/// セッション詳細のモデルと、解析画面のアダプターの両方が使います。
nonisolated struct DrivingRouteStatusResolver: Sendable {
    /// 軌跡を区間に分ける計算です。
    private let segmenter: DrivingRouteSegmenter
    /// 理由と注記の判定です。
    private let assessor: DrivingRouteAssessor
    /// 理由と注記のキーへの写しです。
    private let textKeys: DrivingRouteTextKeys

    /// 区切り・判定・キーの部品を固定して生成します。
    ///
    /// 責務: 状態の決定に使う純粋な部品を保持します。
    /// - Parameters:
    ///   - segmenter: 軌跡を区間に分ける計算。
    ///   - assessor: 理由と注記の判定。
    ///   - textKeys: 理由と注記のキーへの写し。
    init(
        segmenter: DrivingRouteSegmenter = .init(),
        assessor: DrivingRouteAssessor = .init(),
        textKeys: DrivingRouteTextKeys = .init()
    ) {
        self.segmenter = segmenter
        self.assessor = assessor
        self.textKeys = textKeys
    }

    /// 軌跡の取得結果から表示の状態を決めます。
    ///
    /// 責務: iCloud に無い時は理由 `notInCloud` を、軌跡がある時は区切って判定した結果を返します。
    /// - Parameter availability: 軌跡の取得結果。
    /// - Returns: 描くルート(描ける点がある時だけ)、描けない理由、表示順の注記キー。
    func status(for availability: ConnectionSessionLocationTrackAvailability) -> DrivingRouteStatus {
        switch availability {
        case .notInCloud:
            DrivingRouteStatus(route: nil, absence: textKeys.absence(.notInCloud), noticeKeys: [])
        case .available(let track, let source):
            status(for: track, source: source)
        }
    }

    /// 使える軌跡を区切って判定し、表示の状態にします。
    ///
    /// 責務: 区切り・判定を行い、出どころに応じて未確認の注記を足し、キーへ写します。
    /// - Parameters:
    ///   - track: 使える軌跡。
    ///   - source: 軌跡の出どころ。
    /// - Returns: 表示の状態。
    private func status(
        for track: ConnectionSessionLocationTrack,
        source: ConnectionSessionLocationTrackSource
    ) -> DrivingRouteStatus {
        let route = segmenter.route(from: track)
        let assessment = assessor.assess(track: track, route: route)
        var notices = assessment.notices
        if source == .restoredEarlier(isVerifiedLatest: false) {
            notices.append(.unverifiedRestoredCopy)
        }
        let noticeKeys = notices.map(textKeys.notice)
        guard let reason = assessment.absenceReason else {
            return DrivingRouteStatus(route: route, absence: nil, noticeKeys: noticeKeys)
        }
        return DrivingRouteStatus(route: nil, absence: textKeys.absence(reason), noticeKeys: noticeKeys)
    }
}
