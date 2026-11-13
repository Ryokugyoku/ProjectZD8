/// session取得evidence repositoryの排他的失敗理由です。
nonisolated enum ConnectionSessionAcquisitionRepositoryError: Error, Equatable, Sendable {
    /// 同じsessionへ同じmanifestと境界eventの組が既に保存されています。
    case duplicate
    /// 同じsessionへ異なるmanifestまたは同種の境界eventが既に保存されています。
    case conflict
    /// 指定sessionの取得evidenceが登録されていません。
    case notFound
    /// 開始eventがないsessionへ終了eventを追記しようとしました。
    case startEvidenceMissing
    /// 終了時刻が保存済み開始時刻より前です。
    case endBeforeStart
    /// 保存先を利用できません。
    case unavailable
}
