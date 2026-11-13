import Foundation

/// ローカルとCloudKitの車両別整備記録を最終更新日時で双方向統合します。
@MainActor
struct SynchronizeMaintenanceRecordsUseCase {
    /// 端末内のGRDB整備保存先です。
    private let localRepository: any MaintenanceRecordRepository
    /// 端末間で共有する遠隔保存先です。
    private let remoteStore: any MaintenanceRemoteStore

    /// ローカル保存先と遠隔保存先を注入します。
    ///
    /// 責務: 整備記録の双方向同期に必要な2つの境界を固定します。
    /// - Parameters:
    ///   - localRepository: GRDBなどの端末内保存先。
    ///   - remoteStore: CloudKitなどの端末間共有先。
    init(localRepository: any MaintenanceRecordRepository, remoteStore: any MaintenanceRemoteStore) {
        self.localRepository = localRepository
        self.remoteStore = remoteStore
    }

    /// ローカルと遠隔の記録を統合して両方へ同一集合を保存します。
    ///
    /// 責務: 1件のアカウントについて記録IDごとの最新更新を採用し双方向へ反映します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: 削除墓石を除き実施日時の新しい順に並べた整備記録。
    /// - Throws: ローカルまたは遠隔の読書きに失敗した場合のエラー。
    func execute(accountIdentifier: String) async throws -> [MaintenanceRecord] {
        async let localTask = localRepository.records(for: accountIdentifier)
        let remote = try await remoteStore.fetchRecords(for: accountIdentifier)
        let local = try await localTask
        let merged = Self.merge(local: local, remote: remote)
        try await localRepository.replaceAll(merged, for: accountIdentifier)
        try await remoteStore.saveRecords(merged, for: accountIdentifier)
        return merged
            .filter { $0.deletedAt == nil }
            .sorted { $0.performedAt > $1.performedAt }
    }

    /// 同一IDの新しい更新だけを採用して同期集合を作成します。
    ///
    /// 責務: 2つの整備集合を更新日時基準の決定的な1集合へ統合します。
    /// - Parameters:
    ///   - local: 端末内の整備集合。
    ///   - remote: 遠隔保存された整備集合。
    /// - Returns: 記録IDが重複しない同期対象集合。
    static func merge(local: [MaintenanceRecord], remote: [MaintenanceRecord]) -> [MaintenanceRecord] {
        var byID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        for record in local {
            guard let current = byID[record.id] else {
                byID[record.id] = record
                continue
            }
            if record.updatedAt >= current.updatedAt {
                byID[record.id] = record
            }
        }
        return byID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}
