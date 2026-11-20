import Foundation
@testable import ProjectZD8

/// 常時表示の境界の偽物です。呼び出しを記録し、指定した失敗を返します。
///
/// `holdsStart` を真にすると、開始はテストが `releaseHeldStart()` で再開させるまで戻りません(開始の最中の競合を再現するため)。
/// 保留したまま終えないよう、テストの終了時に `releaseAllHeldStarts()` を呼びます。
/// `holdsOrphanCleanup` を真にすると、残った表示の片付けも `releaseAllHeldOrphanCleanups()` まで戻りません(片付けと開始の順序を確かめるため)。
@MainActor
final class SessionActivityPortSpy: SessionActivityPort {
    /// 境界へ届いた操作の種類と内容です(届いた順)。
    enum Call: Equatable {
        /// 開始です。
        case start(RecordingSessionActivityContent)
        /// 更新です。
        case update(RecordingSessionActivityContent)
        /// 終了です。
        case end(RecordingSessionActivityContent)
        /// 前回のプロセスが残した表示の片付けです。
        case endOrphanedPresentations
    }

    /// 表示が出ているかどうかです。開始成功で真、終了成功で偽になります。
    var isPresenting = false
    /// 開始が受け取った内容です。
    private(set) var startedContents: [RecordingSessionActivityContent] = []
    /// 更新が受け取った内容です。
    private(set) var updatedContents: [RecordingSessionActivityContent] = []
    /// 開始が受け取った表示の有効期限です(開始の順)。
    private(set) var startedStaleDates: [Date] = []
    /// 更新が受け取った表示の有効期限です(更新の順)。
    private(set) var updatedStaleDates: [Date] = []
    /// 残った表示の片付けが呼ばれた回数です。
    private(set) var endOrphanedPresentationsCount = 0
    /// 終了が受け取った最終内容です。
    private(set) var endedContents: [RecordingSessionActivityContent] = []
    /// 終了が受け取った消去時刻です(終了の順)。
    private(set) var endedDismissDates: [Date] = []
    /// 開始・更新・終了が届いた順の記録です。
    private(set) var calls: [Call] = []
    /// 設定すると開始がこのエラーを投げます。
    var startError: (any Error)?
    /// 設定すると更新がこのエラーを投げます。
    var updateError: (any Error)?
    /// 設定すると終了がこのエラーを投げます。
    var endError: (any Error)?
    /// 真の間、開始はテストが再開させるまで戻りません。
    var holdsStart = false
    /// 再開を待っている開始の継続です(古い順)。
    private var heldStarts: [CheckedContinuation<Void, Never>] = []
    /// 真の間、残った表示の片付けはテストが再開させるまで戻りません。
    var holdsOrphanCleanup = false
    /// 再開を待っている片付けの継続です(古い順)。
    private var heldOrphanCleanups: [CheckedContinuation<Void, Never>] = []

    /// 再開を待っている開始の件数です。
    var heldStartCount: Int { heldStarts.count }
    /// 再開を待っている片付けの件数です。
    var heldOrphanCleanupCount: Int { heldOrphanCleanups.count }

    /// 開始を記録します。
    ///
    /// 責務: 内容と有効期限を記録し、保留の指定があれば再開まで待ち、エラー指定が無ければ表示中にします。
    func start(_ content: RecordingSessionActivityContent, staleDate: Date) async throws {
        startedContents.append(content)
        startedStaleDates.append(staleDate)
        calls.append(.start(content))
        if holdsStart {
            await withCheckedContinuation { heldStarts.append($0) }
        }
        if let startError { throw startError }
        isPresenting = true
    }

    /// 更新を記録します。
    ///
    /// 責務: 内容と有効期限を記録し、エラー指定があれば投げます。
    func update(_ content: RecordingSessionActivityContent, staleDate: Date) async throws {
        updatedContents.append(content)
        updatedStaleDates.append(staleDate)
        calls.append(.update(content))
        if let updateError { throw updateError }
    }

    /// 終了を記録します。
    ///
    /// 責務: 最終内容と消去時刻を記録し、エラー指定が無ければ表示を閉じます。
    func end(_ finalContent: RecordingSessionActivityContent, dismissAt: Date) async throws {
        endedContents.append(finalContent)
        endedDismissDates.append(dismissAt)
        calls.append(.end(finalContent))
        if let endError { throw endError }
        isPresenting = false
    }

    /// 残った表示の片付けを記録します。
    ///
    /// 責務: 呼び出しを記録し、保留の指定があれば再開まで待ちます。このプロセスの表示(`isPresenting`)は変えません。
    func endOrphanedPresentations() async {
        endOrphanedPresentationsCount += 1
        calls.append(.endOrphanedPresentations)
        if holdsOrphanCleanup {
            await withCheckedContinuation { heldOrphanCleanups.append($0) }
        }
    }

    /// 保留中の片付けをすべて再開させ、以後の片付けは保留しません。
    ///
    /// 責務: テスト終了後に再開されない継続を残さないようにします。
    func releaseAllHeldOrphanCleanups() {
        holdsOrphanCleanup = false
        let held = heldOrphanCleanups
        heldOrphanCleanups.removeAll()
        held.forEach { $0.resume() }
    }

    /// 最も古い保留中の開始を再開させます。
    ///
    /// 責務: 保留が無ければ何もしません。
    func releaseHeldStart() {
        guard !heldStarts.isEmpty else { return }
        heldStarts.removeFirst().resume()
    }

    /// 保留中の開始をすべて再開させ、以後の開始は保留しません。
    ///
    /// 責務: テスト終了後に再開されない継続を残さないようにします。
    func releaseAllHeldStarts() {
        holdsStart = false
        let held = heldStarts
        heldStarts.removeAll()
        held.forEach { $0.resume() }
    }

    /// システムが表示を終了した状況(8時間上限等)を再現します。
    ///
    /// 責務: 呼び出しを伴わず表示中でなくします。
    func simulateSystemDismissal() {
        isPresenting = false
    }
}
