import CloudKit

/// `CKSyncEngine` の取得範囲を属性レコードのゾーンだけに絞ります。
///
/// アーカイブゾーンの変更を取得するとRawのアセットまでダウンロードされるため、エンジンには一切取得させません。
nonisolated enum CloudKitSyncFetchScope {
    /// 責務: 要求された取得範囲を、属性ゾーンだけを含む範囲へ絞ります。
    /// - Parameters:
    ///   - scope: エンジンが提案した取得範囲。
    ///   - mainZoneID: 属性レコードのゾーン。
    /// - Returns: 属性ゾーンが要求範囲に含まれればそのゾーンだけ、含まれなければ空の範囲。
    static func restrictedToMainZone(
        _ scope: CKSyncEngine.FetchChangesOptions.Scope,
        mainZoneID: CKRecordZone.ID = CloudKitSyncConfiguration.zoneID
    ) -> CKSyncEngine.FetchChangesOptions.Scope {
        .zoneIDs(scope.contains(mainZoneID) ? [mainZoneID] : [])
    }
}
