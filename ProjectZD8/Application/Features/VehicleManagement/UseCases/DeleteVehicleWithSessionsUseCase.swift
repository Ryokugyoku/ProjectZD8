/// 1台の登録車両とその接続セッションを全端末から削除します。
@MainActor
struct DeleteVehicleWithSessionsUseCase {
    /// 車両一括削除を安全に開始できない状態です。
    enum Error: Swift.Error, Equatable {
        /// 対象車両に取得中の接続セッションがあります。
        case activeSession
    }

    /// 削除対象セッションを取得するローカル履歴境界です。
    private let sessionRepository: any ConnectionSessionRepository
    /// 現在端末のセッションを物理削除する境界です。
    private let localSessionErasureRepository: any ConnectionSessionErasureRepository
    /// 全端末へセッション削除を伝播するCloudKit境界です。
    private let sessionTransferRepository: any ConnectionSessionTransferRepository
    /// 車両プロフィールを削除する同期境界です。
    private let vehicleRepository: any VehicleRepository

    /// 車両削除に必要な履歴、全端末転送、車両保存の各境界を固定します。
    ///
    /// 責務: 1件の車両一括削除処理をセッションと車両の永続化境界へ結び付けます。
    /// - Parameters:
    ///   - sessionRepository: 削除対象セッションを取得するローカル履歴境界。
    ///   - localSessionErasureRepository: 現在端末のセッション物理削除境界。
    ///   - sessionTransferRepository: 全端末へセッション削除を伝播するCloudKit境界。
    ///   - vehicleRepository: 最後に車両プロフィールを削除する同期境界。
    init(
        sessionRepository: any ConnectionSessionRepository,
        localSessionErasureRepository: any ConnectionSessionErasureRepository,
        sessionTransferRepository: any ConnectionSessionTransferRepository,
        vehicleRepository: any VehicleRepository
    ) {
        self.sessionRepository = sessionRepository
        self.localSessionErasureRepository = localSessionErasureRepository
        self.sessionTransferRepository = sessionTransferRepository
        self.vehicleRepository = vehicleRepository
    }

    /// 対象車両の全終了済みセッションを全端末削除してから車両プロフィールを削除します。
    ///
    /// 責務: 1件の車両IDを関連セッション削除済みの車両削除結果へ変換します。
    /// - Parameters:
    ///   - vehicleID: 削除する登録車両の安定識別子。
    ///   - accountIdentifier: 車両とセッションを所有するAppleアカウント識別子。
    /// - Throws: 取得中セッションがある場合、または履歴・CloudKit・ローカル・車両の削除に失敗した場合のエラー。
    func execute(vehicleID: VehicleID, accountIdentifier: String) async throws {
        let sessions = try sessionRepository.sessions(for: accountIdentifier).filter {
            $0.vehicle?.id == vehicleID
        }
        guard sessions.allSatisfy({ $0.endedAt != nil }) else {
            throw Error.activeSession
        }

        for session in sessions {
            try await sessionTransferRepository.deleteSession(
                session.id,
                for: accountIdentifier
            )
            try localSessionErasureRepository.deleteSession(
                session.id,
                for: accountIdentifier
            )
        }
        try await vehicleRepository.deleteVehicle(
            id: vehicleID,
            for: accountIdentifier
        )
    }
}
