import Foundation
import Observation

/// 接続セッションの開始、車両関連付け、終了を永続化へ結び付けます。
@MainActor
@Observable
final class ConnectionSessionLifecycleModel {
    /// 現在接続中として管理しているセッションです。
    private(set) var activeSession: ConnectionSession?
    /// セッションの永続化境界です。
    @ObservationIgnored private let repository: any ConnectionSessionRepository
    /// 現在日時を生成する注入済み処理です。
    @ObservationIgnored private let now: () -> Date
    /// 新規セッションIDを生成する注入済み処理です。
    @ObservationIgnored private let makeID: () -> ConnectionSessionID
    /// 履歴の再読込が必要になったことを通知する処理です。
    @ObservationIgnored private let historyDidChange: @MainActor () -> Void
    /// 現在のAppleアカウント識別子です。
    @ObservationIgnored private var accountIdentifier: String?

    /// セッション保存先と副作用依存を固定して生成します。
    ///
    /// 責務: 接続ライフサイクル操作を1件のセッション永続化境界へ結び付けます。
    /// - Parameters:
    ///   - repository: セッションの保存と取得を行う境界。
    ///   - now: 開始日時と終了日時を生成する処理。
    ///   - makeID: 新しいセッションIDを生成する処理。省略時はUUIDを生成します。
    ///   - historyDidChange: 保存後に履歴再読込を通知する処理。
    init(
        repository: any ConnectionSessionRepository,
        now: @escaping () -> Date = Date.init,
        makeID: (() -> ConnectionSessionID)? = nil,
        historyDidChange: @escaping @MainActor () -> Void = {}
    ) {
        self.repository = repository
        self.now = now
        self.makeID = makeID ?? { ConnectionSessionID() }
        self.historyDidChange = historyDidChange
    }

    /// 型付き操作をセッション永続化へ変換します。
    ///
    /// 責務: 1件のLogging操作を対応するライフサイクル変更へ振り分けます。
    /// - Parameter action: AppまたはApplicationから通知された操作。
    func send(_ action: ConnectionSessionLifecycleAction) {
        switch action {
        case let .accountIdentifierChanged(identifier): activateAccount(identifier)
        case .startRequested: startSession()
        case let .vehicleResolved(vehicle): bindVehicle(vehicle)
        case let .odometerObserved(kilometers): recordOdometer(kilometers)
        case let .endRequested(reason): endSession(reason: reason)
        }
    }

    /// 新しいアカウントを有効化し、残存中セッションを異常終了へ閉じます。
    ///
    /// 責務: 1件のアカウント変更をセッション保存範囲と再起動回復へ反映します。
    /// - Parameter identifier: 新しいAppleアカウント識別子。
    private func activateAccount(_ identifier: String?) {
        guard identifier != accountIdentifier else { return }
        accountIdentifier = identifier
        activeSession = nil
        guard let identifier, !identifier.isEmpty else { return }
        do {
            let unfinished = try repository.sessions(for: identifier).filter { $0.endedAt == nil }
            for var session in unfinished {
                session.endedAt = now()
                session.endReason = .unexpectedTermination
                try repository.save(session)
            }
            if !unfinished.isEmpty { historyDidChange() }
        } catch {
            return
        }
    }

    /// 現在アカウントへ新しい未終了セッションを保存します。
    ///
    /// 責務: 1回のHOME接続開始を新規セッションとして永続化します。
    private func startSession() {
        guard let accountIdentifier, !accountIdentifier.isEmpty else { return }
        if activeSession != nil { endSession(reason: .superseded) }
        let session = ConnectionSession(
            id: makeID(),
            accountIdentifier: accountIdentifier,
            startedAt: now()
        )
        do {
            try repository.save(session)
            activeSession = session
            historyDidChange()
        } catch {
            activeSession = nil
        }
    }

    /// 確定した登録車両を現在の未終了セッションへ保存します。
    ///
    /// 責務: 1台の登録車両スナップショットを現在セッションへ関連付けます。
    /// - Parameter vehicle: 接続対象として確定した登録車両。
    private func bindVehicle(_ vehicle: VehicleProfile) {
        guard var session = activeSession else { return }
        session.vehicle = ConnectionSessionVehicle(profile: vehicle)
        do {
            try repository.save(session)
            activeSession = session
            historyDidChange()
        } catch {
            return
        }
    }

    /// 累積走行距離の先頭値と最新値を現在セッションへ保存します。
    ///
    /// 責務: 1件の有効な累積走行距離観測をセッション差分算出用の境界値へ反映します。
    /// - Parameter kilometers: Service 01 PID A6から取得したキロメートル単位の累積走行距離。
    private func recordOdometer(_ kilometers: Double) {
        guard kilometers.isFinite, kilometers >= 0, var session = activeSession else { return }
        if session.startingOdometerKilometers == nil {
            session.startingOdometerKilometers = kilometers
        }
        guard session.endingOdometerKilometers != kilometers else { return }
        session.endingOdometerKilometers = kilometers
        do {
            try repository.save(session)
            activeSession = session
            historyDidChange()
        } catch {
            return
        }
    }

    /// 現在セッションへ終了日時と原因を保存します。
    ///
    /// 責務: 1件の未終了セッションを指定原因で終端状態へ遷移させます。
    /// - Parameter reason: セッションが終了した直接原因。
    private func endSession(reason: ConnectionSessionEndReason) {
        guard var session = activeSession else { return }
        session.endedAt = now()
        session.endReason = reason
        do {
            try repository.save(session)
            activeSession = nil
            historyDidChange()
        } catch {
            activeSession = session
        }
    }
}
