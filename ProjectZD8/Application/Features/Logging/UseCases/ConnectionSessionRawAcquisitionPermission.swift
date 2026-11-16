import Foundation

/// manifest保存と開始境界保存が完了したRaw取得許可です。
nonisolated struct ConnectionSessionRawAcquisitionPermission: Equatable, Sendable {
    /// 許可対象のsession識別子です。
    let sessionID: ConnectionSessionID
    /// 許可対象のpolling世代です。
    let generation: UInt
    /// 保存済みのimmutable manifestです。
    let manifest: ConnectionSessionAcquisitionManifest

    /// 保存完了済みのRaw取得許可を生成します。
    ///
    /// 責務: 保存済みmanifestを同じsessionとpolling世代のRaw開始許可へ結び付けます。
    /// - Parameters:
    ///   - sessionID: 許可対象のsession識別子。
    ///   - generation: 許可対象のpolling世代。
    ///   - manifest: 保存済みのimmutable manifest。
    init(
        sessionID: ConnectionSessionID,
        generation: UInt,
        manifest: ConnectionSessionAcquisitionManifest
    ) {
        self.sessionID = sessionID
        self.generation = generation
        self.manifest = manifest
    }
}
