import Foundation
@testable import ProjectZD8

/// 走行ルートの読み込みを、セッションごとに止めておき、指定した時に再開させる門です。
///
/// 止めたまま終わらないよう、テストの tearDown で `releaseAll()` を必ず呼びます。
@MainActor
final class DrivingRouteLoadGate {
    /// 止めておくセッションです。
    private var heldSessionIDs: Set<ConnectionSessionID> = []
    /// 止めている読み込みの継続です。
    private var waiting: [ConnectionSessionID: [CheckedContinuation<Void, Never>]] = [:]

    /// 何も止めない門を作ります。
    ///
    /// 責務: 止めるセッションも待ちも無い状態を作ります。
    init() {}

    /// 止めている読み込みの数です。
    var waitingCount: Int {
        waiting.values.reduce(0) { $0 + $1.count }
    }

    /// このセッションの読み込みを、再開するまで止めるようにします。
    ///
    /// 責務: 以後に届いた読み込みを止める対象へ加えます。
    /// - Parameter sessionID: 止めるセッション。
    func hold(_ sessionID: ConnectionSessionID) {
        heldSessionIDs.insert(sessionID)
    }

    /// 止める対象なら、再開されるまで待ちます。
    ///
    /// 責務: 止める対象でなければすぐ戻り、対象なら継続を預けて待ちます。
    /// - Parameter sessionID: 読み込むセッション。
    func waitIfHeld(_ sessionID: ConnectionSessionID) async {
        guard heldSessionIDs.contains(sessionID) else { return }
        await withCheckedContinuation { continuation in
            waiting[sessionID, default: []].append(continuation)
        }
    }

    /// このセッションの読み込みを再開し、以後は止めません。
    ///
    /// 責務: 止める対象から外し、預かった継続をすべて再開します。
    /// - Parameter sessionID: 再開するセッション。
    func release(_ sessionID: ConnectionSessionID) {
        heldSessionIDs.remove(sessionID)
        waiting.removeValue(forKey: sessionID)?.forEach { $0.resume() }
    }

    /// 全てのセッションの読み込みを再開します。
    ///
    /// 責務: 止めたままテストが終わらないよう、預かった継続をすべて再開します。
    func releaseAll() {
        heldSessionIDs.removeAll()
        let continuations = waiting.values.flatMap { $0 }
        waiting.removeAll()
        continuations.forEach { $0.resume() }
    }
}
