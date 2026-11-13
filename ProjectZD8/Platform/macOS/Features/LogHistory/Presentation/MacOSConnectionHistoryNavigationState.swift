#if os(macOS)
/// macOS接続履歴内で表示できる階層遷移先です。
enum MacOSConnectionHistoryRoute: Hashable {
    /// 指定車両のセッション一覧です。
    case vehicleSessions(ConnectionHistoryVehicleGroupID)
    /// 指定セッションの詳細です。
    case sessionDetail(ConnectionSessionID)
}

/// macOS接続履歴内の一時的な画面遷移経路を管理します。
struct MacOSConnectionHistoryNavigationState: Equatable {
    /// ルート画面から現在画面までの遷移先です。
    var path: [MacOSConnectionHistoryRoute] = []

    /// 車両別アーカイブまで遷移経路を戻します。
    ///
    /// 責務: 現在の接続履歴内遷移経路をルート状態へ戻します。
    mutating func returnToVehicleArchive() {
        path.removeAll()
    }

    /// セッション詳細から直前の車両セッション一覧へ戻します。
    ///
    /// 責務: 現在の末尾がセッション詳細である場合に限り、その遷移だけを取り除きます。
    mutating func returnToVehicleSessionList() {
        guard let lastRoute = path.last,
              case .sessionDetail = lastRoute else { return }
        path.removeLast()
    }

    /// 表示中の詳細セッションが一覧から削除された場合に直前の車両セッション一覧へ戻します。
    ///
    /// 責務: 現在表示中のセッション詳細を最新の利用可能IDと照合し、削除済み詳細遷移を取り除きます。
    /// - Parameter availableSessionIDs: 最新の履歴状態に残っているセッションID集合。
    mutating func returnFromDeletedSession(availableSessionIDs: Set<ConnectionSessionID>) {
        guard let lastRoute = path.last,
              case let .sessionDetail(sessionID) = lastRoute,
              !availableSessionIDs.contains(sessionID) else { return }
        path.removeLast()
    }
}
#endif
