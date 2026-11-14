import Foundation
@testable import ProjectZD8

/// commitされたチャンクを記録し、指定した回のcommitだけ失敗させる取得チャンクRepositoryです。
///
/// 下位Repositoryを渡すと成功するcommitをそこへ委ね、失敗させる回は下位へ渡さずに失敗します。
final class AcquisitionChunkRepositorySpy: ConnectionSessionAcquisitionChunkRepository, @unchecked Sendable {
    /// 記録を保護するロックです。
    private let lock = NSLock()
    /// 成功するcommitを委ねる下位Repositoryです。
    private let base: (any ConnectionSessionAcquisitionChunkRepository)?
    /// 失敗させるcommitの回(0始まり)です。
    private let failingAttempts: Set<Int>
    /// ロックで保護したcommitを試みたチャンクです。
    private var storedAttempts: [ConnectionSessionAcquisitionChunk] = []

    /// 下位Repositoryと失敗させる回を固定します。
    ///
    /// 責務: commitを記録し、指定した回だけ保存失敗にするRepositoryを構築します。
    /// - Parameters:
    ///   - base: 成功するcommitを委ねる下位Repository。
    ///   - failingAttempts: 失敗させるcommitの回(0始まり)。
    init(base: (any ConnectionSessionAcquisitionChunkRepository)? = nil, failingAttempts: Set<Int> = []) {
        self.base = base
        self.failingAttempts = failingAttempts
    }

    /// commitを試みたチャンクです。試みた順に並びます。
    var attempts: [ConnectionSessionAcquisitionChunk] {
        lock.withLock { storedAttempts }
    }

    /// 成功したcommitのチャンクです。試みた順に並びます。
    var committed: [ConnectionSessionAcquisitionChunk] {
        lock.withLock {
            storedAttempts.enumerated().filter { !failingAttempts.contains($0.offset) }.map(\.element)
        }
    }

    /// チャンクのcommitを記録し、指定した回なら失敗させます。
    ///
    /// 責務: 試行を記録し、失敗させる回は保存先利用不能を送出し、それ以外は下位Repositoryへ委ねます。
    /// - Parameter chunk: 保存するチャンク。
    /// - Throws: 失敗させる回は `.unavailable`、または下位Repositoryの失敗。
    func commit(_ chunk: ConnectionSessionAcquisitionChunk) throws {
        let attempt = lock.withLock {
            storedAttempts.append(chunk)
            return storedAttempts.count - 1
        }
        if failingAttempts.contains(attempt) { throw ConnectionSessionAcquisitionChunkRepositoryError.unavailable }
        try base?.commit(chunk)
    }
}
