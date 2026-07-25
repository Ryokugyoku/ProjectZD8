import Foundation

/// 接続履歴の端末間同期表示段階です。
enum ConnectionHistorySyncPhase: Equatable, Sendable {
    /// 同期要求前または変更なしです。
    case idle
    /// CloudKitへ送受信しています。
    case syncing
    /// 直近のCloudKit同期を完了しました。
    case synchronized
    /// 直近のCloudKit同期が失敗し再試行を待っています。
    case failed
}

/// 自動判別できなかったセッション停止をユーザーへ確認する内容です。
struct ConnectionSessionStopReviewPrompt: Equatable, Sendable {
    /// 確認対象の接続セッションIDです。
    let sessionID: ConnectionSessionID
    /// アプリが観測した直接の終了理由です。
    let observedReason: ConnectionSessionEndReason

    /// セッションと観測済み終了理由を確認内容として生成します。
    ///
    /// 責務: 1件の確認可能な接続セッションを停止確認表示に必要な値へ固定します。
    /// - Parameters:
    ///   - sessionID: 確認対象の接続セッションID。
    ///   - observedReason: アプリが観測した直接の終了理由。
    init(sessionID: ConnectionSessionID, observedReason: ConnectionSessionEndReason) {
        self.sessionID = sessionID
        self.observedReason = observedReason
    }
}

/// iPhoneローカルRawログ除去前に表示する確認内容です。
struct ConnectionSessionRawRemovalPrompt: Equatable, Sendable {
    /// 除去候補の接続セッションIDです。
    let sessionID: ConnectionSessionID
    /// CloudKit保管証跡に基づく除去判断です。
    let decision: ConnectionSessionLocalRemovalDecision
    /// 除去対象のRaw応答件数です。
    let recordCount: Int64
    /// 除去対象のRaw Payload合計バイト数です。
    let byteCount: Int64

    /// セッションと安全判断を確認表示値として生成します。
    ///
    /// 責務: 1件のローカル除去候補を警告に必要な件数と容量へまとめます。
    /// - Parameters:
    ///   - sessionID: 除去候補の接続セッションID。
    ///   - decision: CloudKit保管証跡に基づく除去判断。
    ///   - recordCount: 除去対象のRaw応答件数。
    ///   - byteCount: 除去対象のRaw Payload合計バイト数。
    init(
        sessionID: ConnectionSessionID,
        decision: ConnectionSessionLocalRemovalDecision,
        recordCount: Int64,
        byteCount: Int64
    ) {
        self.sessionID = sessionID
        self.decision = decision
        self.recordCount = recordCount
        self.byteCount = byteCount
    }
}

/// macOSで全端末削除前に表示するセッション情報です。
struct ConnectionSessionDeletionPrompt: Equatable, Sendable {
    /// 削除対象の接続セッションIDです。
    let sessionID: ConnectionSessionID
    /// 物理削除するRawログの収集件数です。
    let recordCount: Int64
    /// 物理削除するRaw Payload合計バイト数です。
    let byteCount: Int64

    /// 削除対象を警告表示に必要な値へまとめます。
    ///
    /// 責務: 1件の削除候補を全端末削除警告に必要な識別子とRaw集計へ変換します。
    /// - Parameters:
    ///   - sessionID: 削除対象の接続セッションID。
    ///   - recordCount: 物理削除するRawログの収集件数。
    ///   - byteCount: 物理削除するRaw Payload合計バイト数。
    init(sessionID: ConnectionSessionID, recordCount: Int64, byteCount: Int64) {
        self.sessionID = sessionID
        self.recordCount = recordCount
        self.byteCount = byteCount
    }
}

/// 終了済みセッション一覧へ適用する終了理由条件です。
enum ConnectionHistoryEndReasonFilter: String, CaseIterable, Equatable, Sendable {
    /// すべての終了理由を表示します。
    case all
    /// ユーザー操作による正常終了だけを表示します。
    case userDisconnected
    /// 車両の応答不能による終了だけを表示します。
    case vehicleNoResponse
    /// 接続喪失による終了だけを表示します。
    case connectionLost
    /// 取得開始失敗による終了だけを表示します。
    case acquisitionFailed
    /// 新しい接続による置換終了だけを表示します。
    case superseded
    /// サインアウトによる終了だけを表示します。
    case accountSignedOut
    /// 予期しない終了だけを表示します。
    case unexpectedTermination

    /// 終了理由が現在の条件へ一致するかを返します。
    ///
    /// 責務: 1件の終了理由を選択中の終了理由条件で判定します。
    /// - Parameter reason: 判定するセッション終了理由。
    /// - Returns: 一覧へ含める場合は `true`。
    func matches(_ reason: ConnectionSessionEndReason?) -> Bool {
        switch self {
        case .all: true
        case .userDisconnected: reason == .userDisconnected
        case .vehicleNoResponse: reason == .vehicleNoResponse
        case .connectionLost: reason == .connectionLost
        case .acquisitionFailed: reason == .acquisitionFailed
        case .superseded: reason == .superseded
        case .accountSignedOut: reason == .accountSignedOut
        case .unexpectedTermination: reason == .unexpectedTermination
        }
    }
}

/// 終了済みセッション一覧へ適用する並び順です。
enum ConnectionHistorySortOrder: String, CaseIterable, Equatable, Sendable {
    /// 開始日時が新しい順です。
    case newest
    /// 開始日時が古い順です。
    case oldest
    /// 走行時間が長い順です。
    case longestDuration
    /// 走行時間が短い順です。
    case shortestDuration
}

/// 車両別履歴グループの安定識別子です。
enum ConnectionHistoryVehicleGroupID: Hashable, Sendable {
    /// Garage登録車両へ関連付いた履歴です。
    case registered(VehicleID)
    /// 車両関連付け前に終了した履歴です。
    case unassigned
}

/// 終了済み接続履歴を1台の車両単位へ集約した表示状態です。
struct ConnectionHistoryVehicleGroup: Identifiable, Equatable, Sendable {
    /// 車両グループの安定識別子です。
    let id: ConnectionHistoryVehicleGroupID
    /// 最新セッション時点の車両表示情報です。
    let vehicle: ConnectionSessionVehicle?
    /// 開始日時が新しい順の終了済みセッションです。
    let sessions: [ConnectionSession]

    /// グループ内のセッション件数です。
    var sessionCount: Int { sessions.count }
    /// グループ内で正常終了しなかったセッション件数です。
    var interruptedCount: Int { sessions.filter { $0.status == .interrupted }.count }
    /// グループ内の記録済み総走行時間です。
    var totalDuration: TimeInterval { sessions.reduce(0) { $0 + $1.recordedDuration } }
    /// 全セッションで差分を確定できた場合の記録済み総走行距離です。
    var totalDistanceKilometers: Double? {
        let distances = sessions.compactMap(\.recordedDistanceKilometers)
        guard distances.count == sessions.count else { return nil }
        return distances.reduce(0, +)
    }
    /// グループ内で最後に接続を開始した日時です。
    var latestStartedAt: Date? { sessions.first?.startedAt }
}

/// 接続履歴画面へ公開する読込済み状態です。
struct ConnectionHistoryState: Equatable {
    /// 履歴取得の現在段階です。
    enum Phase: Equatable {
        /// アカウント確定前または読込待ちです。
        case idle
        /// 永続化済み履歴を読み込んでいます。
        case loading
        /// 履歴の読込が完了しました。
        case loaded
        /// 履歴保存先を利用できません。
        case failed
    }

    /// 履歴取得の現在段階です。
    var phase: Phase = .idle
    /// 開始日時が新しい順の接続セッションです。
    var sessions: [ConnectionSession] = []
    /// 直近の読込失敗を示すローカライズキーです。
    var failureKey: String?
    /// 絞り込み範囲の開始日です。
    var filterStartDate: Date?
    /// 絞り込み範囲の終了日です。
    var filterEndDate: Date?
    /// 選択中の終了理由条件です。
    var endReasonFilter: ConnectionHistoryEndReasonFilter = .all
    /// 選択中の並び順です。
    var sortOrder: ConnectionHistorySortOrder = .newest
    /// CloudKitセッション同期の現在段階です。
    var syncPhase: ConnectionHistorySyncPhase = .idle
    /// ユーザー操作による停止かを確認する表示内容です。
    var stopReviewPrompt: ConnectionSessionStopReviewPrompt?
    /// 直近の停止確認保存失敗を示すローカライズキーです。
    var stopReviewFailureKey: String?
    /// iPhoneローカルRawログ除去前の確認内容です。
    var rawRemovalPrompt: ConnectionSessionRawRemovalPrompt?
    /// macOS全端末セッション削除前の確認内容です。
    var sessionDeletionPrompt: ConnectionSessionDeletionPrompt?
    /// 全端末セッション削除中の対象IDです。
    var deletingSessionID: ConnectionSessionID?
    /// 直近の全端末削除失敗を示すローカライズキーです。
    var sessionDeletionFailureKey: String?

    /// 現在接続中のセッションです。
    var activeSessions: [ConnectionSession] { sessions.filter { $0.status == .connected } }
    /// 終了日時が確定したセッションです。
    var closedSessions: [ConnectionSession] { sessions.filter { $0.status != .connected } }
    /// 全履歴のうち正常に終了しなかったセッション件数です。
    var interruptedCount: Int { closedSessions.filter { $0.status == .interrupted }.count }
    /// 終了済みセッションの記録済み総走行時間です。
    var totalRecordedDuration: TimeInterval { closedSessions.reduce(0) { $0 + $1.recordedDuration } }
    /// 絞り込み条件が1件以上有効かを示します。
    var hasActiveFilters: Bool {
        filterStartDate != nil || filterEndDate != nil || endReasonFilter != .all
    }

    /// 終了済み履歴を車両単位へ集約して返します。
    var vehicleGroups: [ConnectionHistoryVehicleGroup] {
        let grouped = Dictionary(grouping: closedSessions) { session in
            session.vehicle.map { ConnectionHistoryVehicleGroupID.registered($0.id) } ?? .unassigned
        }
        return grouped.map { id, sessions in
            let sorted = sessions.sorted { $0.startedAt > $1.startedAt }
            return ConnectionHistoryVehicleGroup(id: id, vehicle: sorted.first?.vehicle, sessions: sorted)
        }
        .sorted { ($0.latestStartedAt ?? .distantPast) > ($1.latestStartedAt ?? .distantPast) }
    }

    /// 指定車両グループへ複合条件と並び順を適用したセッションを返します。
    ///
    /// 責務: 1台分の終了済み履歴を日付範囲と終了理由で絞り込み、指定順へ整列します。
    /// - Parameter groupID: 対象車両グループの識別子。
    /// - Returns: 現在の全条件を同時に満たす終了済みセッション。
    func filteredSessions(for groupID: ConnectionHistoryVehicleGroupID) -> [ConnectionSession] {
        guard let sessions = vehicleGroups.first(where: { $0.id == groupID })?.sessions else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        let filtered = sessions.filter { session in
            let isAfterStart = filterStartDate.map { session.startedAt >= calendar.startOfDay(for: $0) } ?? true
            let isBeforeEnd = filterEndDate.map {
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) else {
                    return session.startedAt <= $0
                }
                return session.startedAt < nextDay
            } ?? true
            return isAfterStart && isBeforeEnd && endReasonFilter.matches(session.endReason)
        }
        return filtered.sorted(by: sessionComparator)
    }

    /// 現在の並び順に対応する2件の比較結果を返します。
    ///
    /// 責務: 2件の終了済みセッションを選択中の単一並び順で比較します。
    /// - Parameters:
    ///   - lhs: 比較する左側セッション。
    ///   - rhs: 比較する右側セッション。
    /// - Returns: 左側を先に表示する場合は `true`。
    private func sessionComparator(_ lhs: ConnectionSession, _ rhs: ConnectionSession) -> Bool {
        switch sortOrder {
        case .newest: lhs.startedAt > rhs.startedAt
        case .oldest: lhs.startedAt < rhs.startedAt
        case .longestDuration: lhs.recordedDuration > rhs.recordedDuration
        case .shortestDuration: lhs.recordedDuration < rhs.recordedDuration
        }
    }
}

private extension ConnectionSession {
    /// 終了日時が確定している範囲の記録時間です。
    var recordedDuration: TimeInterval {
        max(0, endedAt?.timeIntervalSince(startedAt) ?? 0)
    }
}
