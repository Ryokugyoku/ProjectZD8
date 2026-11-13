import CloudKit
import XCTest
@testable import ProjectZD8

/// エンジンの取得範囲の絞り込みを確認します。
final class CloudKitSyncFetchScopeTests: XCTestCase {
    private let main = CloudKitSyncConfiguration.zoneID
    private let archive = CloudKitSyncConfiguration.archiveZoneID

    /// 責務: どの範囲を要求されても、アーカイブゾーンを含まず属性ゾーンだけになることを確認します。
    func testScopeNeverIncludesArchiveZone() {
        let requests: [CKSyncEngine.FetchChangesOptions.Scope] = [
            .all,
            .allExcluding([]),
            .zoneIDs([main, archive]),
            .allExcluding([archive]),
        ]
        for request in requests {
            let scope = CloudKitSyncFetchScope.restrictedToMainZone(request, mainZoneID: main)
            XCTAssertTrue(scope.contains(main))
            XCTAssertFalse(scope.contains(archive))
        }
    }

    /// 責務: 属性ゾーンが要求に含まれなければ何も取得しないことを確認します。
    func testScopeIsEmptyWhenMainZoneNotRequested() {
        for request: CKSyncEngine.FetchChangesOptions.Scope in [.zoneIDs([archive]), .allExcluding([main])] {
            let scope = CloudKitSyncFetchScope.restrictedToMainZone(request, mainZoneID: main)
            XCTAssertFalse(scope.contains(main))
            XCTAssertFalse(scope.contains(archive))
        }
    }
}
