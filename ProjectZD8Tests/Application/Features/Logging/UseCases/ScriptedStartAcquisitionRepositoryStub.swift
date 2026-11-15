import Foundation
@testable import ProjectZD8

/// 取得開始の保存に、指定した失敗(`duplicate`・`conflict` など)を返せる取得証跡の保存先です。
///
/// 失敗を指定していない保存だけが manifest を保持します。失敗を返した保存は保持済みの manifest を書き換えません。
final class ScriptedStartAcquisitionRepositoryStub: ConnectionSessionAcquisitionRepository, @unchecked Sendable {
    /// 状態への並行アクセスを直列化するロックです。
    private let lock = NSLock()
    /// ロックで保護した、次の保存で返す失敗です。
    private var storedSaveError: ConnectionSessionAcquisitionRepositoryError?
    /// ロックで保護した保存済みmanifestです。
    private var stored: ConnectionSessionAcquisitionManifest?
    /// ロックで保護した保存済みの開始時刻です。
    private var storedStartedAt: Date?
    /// ロックで保護した保存の呼び出し回数です。
    private var storedSaveCallCount = 0

    /// 次の保存で返す失敗です。`nil` なら保存します。
    var saveError: ConnectionSessionAcquisitionRepositoryError? {
        get { lock.withLock { storedSaveError } }
        set { lock.withLock { storedSaveError = newValue } }
    }

    /// 保存済みmanifestです。
    var storedManifest: ConnectionSessionAcquisitionManifest? {
        lock.withLock { stored }
    }

    /// 保存済みの開始時刻です。
    var startedAt: Date? {
        lock.withLock { storedStartedAt }
    }

    /// 保存の呼び出し回数です。
    var saveCallCount: Int {
        lock.withLock { storedSaveCallCount }
    }

    /// 取得開始を保存するか、指定の失敗を返します。
    ///
    /// 責務: 失敗の指定がなければmanifestと開始時刻を保持し、指定があれば保持済みの値を変えずに失敗を送出します。
    /// - Parameters:
    ///   - manifest: 保存するmanifest。
    ///   - startedAt: 開始時刻。
    ///   - sessionID: セッションID。
    /// - Throws: 指定した失敗。
    func saveStartOnce(manifest: ConnectionSessionAcquisitionManifest, startedAt: Date, for sessionID: ConnectionSessionID) throws {
        try lock.withLock {
            storedSaveCallCount += 1
            if let storedSaveError { throw storedSaveError }
            stored = manifest
            storedStartedAt = startedAt
        }
    }

    /// 終了の保存は使いません。
    ///
    /// 責務: 呼ばれたら利用不能として失敗します。
    /// - Throws: 常に `unavailable`。
    func appendEnd(at endedAt: Date, reason: ConnectionSessionEndReason, for sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }

    /// 保存済みmanifestを返します。
    ///
    /// 責務: 保持済みのmanifestを返し、無ければ未保存として失敗します。
    /// - Parameter sessionID: セッションID。
    /// - Returns: 保存済みmanifest。
    /// - Throws: 未保存なら `notFound`。
    func manifest(for sessionID: ConnectionSessionID) throws -> ConnectionSessionAcquisitionManifest {
        guard let manifest = storedManifest else { throw ConnectionSessionAcquisitionRepositoryError.notFound }
        return manifest
    }

    /// 境界の証跡は使いません。
    ///
    /// 責務: 保持済みの開始時刻を開始境界として返します。
    /// - Parameter sessionID: セッションID。
    /// - Returns: 開始境界。未保存なら空。
    func boundaryEvidence(for sessionID: ConnectionSessionID) throws -> [AcquisitionRawBoundaryEvidence] {
        startedAt.map { [.started(at: $0)] } ?? []
    }
}
