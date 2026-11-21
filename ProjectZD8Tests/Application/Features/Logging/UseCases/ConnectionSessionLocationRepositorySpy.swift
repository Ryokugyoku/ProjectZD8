import Foundation
@testable import ProjectZD8

/// 位置と位置記録の状態変化をセッションごとにメモリ上へ保持し、メソッドごとに失敗を注入できる Repository です。
nonisolated final class ConnectionSessionLocationRepositorySpy: ConnectionSessionLocationRepository, @unchecked Sendable {
    /// 保持内容と失敗指定を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した、セッションごとの保存済み位置です(追記順)。
    private var storedSamples: [ConnectionSessionID: [LocationFix]] = [:]
    /// ロックで保護した、セッションごとの保存済み状態変化です(追記順)。
    private var storedEvents: [ConnectionSessionID: [ConnectionSessionLocationEvent]] = [:]
    /// ロックで保護した、位置の追記が試みられた回数です。
    private var storedAppendSampleAttemptCount = 0
    /// ロックで保護した、位置の追記を失敗させるかどうかです。
    private var storedFailsAppendSample = false
    /// ロックで保護した、状態変化の追記を失敗させるかどうかです。
    private var storedFailsAppendEvent = false

    /// 空の Repository を生成します。
    ///
    /// 責務: 何も保存されておらず、失敗も注入されていない状態を構築します。
    init() {}

    /// 位置の追記が試みられた回数です(失敗を含む)。
    var appendSampleAttemptCount: Int {
        lock.withLock { storedAppendSampleAttemptCount }
    }

    /// 位置の追記の失敗を切り替えます。
    ///
    /// 責務: 以降の `appendSample` を `.unavailable` で失敗させるかどうかを置き換えます。
    /// - Parameter fails: 失敗させる場合は `true`。
    func setFailsAppendSample(_ fails: Bool) {
        lock.withLock { storedFailsAppendSample = fails }
    }

    /// 状態変化の追記の失敗を切り替えます。
    ///
    /// 責務: 以降の `appendEvent` を `.unavailable` で失敗させるかどうかを置き換えます。
    /// - Parameter fails: 失敗させる場合は `true`。
    func setFailsAppendEvent(_ fails: Bool) {
        lock.withLock { storedFailsAppendEvent = fails }
    }

    /// セッションに保存された位置を追記順に返します。
    ///
    /// 責務: テストの確認用に、保存済みの位置だけを返します。
    /// - Parameter sessionID: 対象の接続セッション。
    /// - Returns: 保存済みの位置。無ければ空配列。
    func storedFixes(for sessionID: ConnectionSessionID) -> [LocationFix] {
        lock.withLock { storedSamples[sessionID] ?? [] }
    }

    /// セッションに保存された状態変化の種類を追記順に返します。
    ///
    /// 責務: テストの確認用に、保存済みの状態変化の種類だけを返します。
    /// - Parameter sessionID: 対象の接続セッション。
    /// - Returns: 保存済みの種類。無ければ空配列。
    func storedEventKinds(for sessionID: ConnectionSessionID) -> [ConnectionSessionLocationEventKind] {
        lock.withLock { (storedEvents[sessionID] ?? []).map(\.kind) }
    }

    /// 位置を1点追記します。
    ///
    /// 責務: 試行回数を数え、失敗の指定があれば `.unavailable` を投げ、なければセッションの末尾へ追加します。
    /// - Parameters:
    ///   - fix: 保存する位置。
    ///   - sessionID: 保存先の接続セッション。
    /// - Throws: 失敗させる場合は `ConnectionSessionRepositoryError.unavailable`。
    func appendSample(_ fix: LocationFix, for sessionID: ConnectionSessionID) throws {
        try lock.withLock {
            storedAppendSampleAttemptCount += 1
            if storedFailsAppendSample { throw ConnectionSessionRepositoryError.unavailable }
            storedSamples[sessionID, default: []].append(fix)
        }
    }

    /// セッションの位置を返します。
    ///
    /// 責務: 追記順に 0 からの連番を付けて返します。
    /// - Parameter sessionID: 対象の接続セッション。
    /// - Returns: 連番昇順の位置。
    func samples(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionLocationSample] {
        storedFixes(for: sessionID).enumerated().map { ConnectionSessionLocationSample(sequence: Int64($0.offset), fix: $0.element) }
    }

    /// 状態変化を1件追記します。
    ///
    /// 責務: 失敗の指定があれば `.unavailable` を投げ、なければ番号を付けてセッションの末尾へ追加します。
    /// - Parameters:
    ///   - kind: 状態の種類。
    ///   - occurredAt: 状態が変化した実時間。
    ///   - sessionID: 保存先の接続セッション。
    /// - Throws: 失敗させる場合は `ConnectionSessionRepositoryError.unavailable`。
    func appendEvent(_ kind: ConnectionSessionLocationEventKind, occurredAt: Date, for sessionID: ConnectionSessionID) throws {
        try lock.withLock {
            if storedFailsAppendEvent { throw ConnectionSessionRepositoryError.unavailable }
            let ordinal = storedEvents[sessionID]?.count ?? 0
            storedEvents[sessionID, default: []].append(
                ConnectionSessionLocationEvent(ordinal: ordinal, occurredAt: occurredAt, kind: kind)
            )
        }
    }

    /// セッションの状態変化を返します。
    ///
    /// 責務: 追記順の状態変化を返します。
    /// - Parameter sessionID: 対象の接続セッション。
    /// - Returns: 番号昇順の状態変化。
    func events(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionLocationEvent] {
        lock.withLock { storedEvents[sessionID] ?? [] }
    }
}
