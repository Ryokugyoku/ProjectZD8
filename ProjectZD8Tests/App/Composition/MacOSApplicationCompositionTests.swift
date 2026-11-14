#if os(macOS)
import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// macOS組立が共有製品DB接続の成否をPID系Repositoryへ正しく反映することを検証します。
@MainActor
final class MacOSApplicationCompositionTests: XCTestCase {
    /// DB Queueを開けない場合に投げるテスト用エラーです。
    private struct OpenFailure: Error {}

    /// 開けない接続ではPID定義Repositoryが利用不能実装になります。
    ///
    /// 責務: 失敗した共有接続を成功や空データへ潰さず `UnavailableOBDPIDDefinitionRepository` にすることを確認します。
    func testPIDDefinitionRepositoryIsUnavailableWhenConnectionFailed() {
        let connection = ApplicationDatabaseConnection(openDatabaseQueue: { throw OpenFailure() })

        let repository = MacOSApplicationComposition.makeOBDPIDDefinitionRepository(database: connection)

        XCTAssertTrue(repository is UnavailableOBDPIDDefinitionRepository)
    }

    /// 開けない接続では車両別PID Repositoryが利用不能実装になります。
    ///
    /// 責務: 失敗した共有接続から `UnavailableVehiclePIDCapabilityRepository` が返ることを確認します。
    func testVehiclePIDCapabilityRepositoryIsUnavailableWhenConnectionFailed() {
        let connection = ApplicationDatabaseConnection(openDatabaseQueue: { throw OpenFailure() })

        let repository = MacOSApplicationComposition.makeVehiclePIDCapabilityRepository(database: connection)

        XCTAssertTrue(repository is UnavailableVehiclePIDCapabilityRepository)
    }

    /// 開ける接続ではPID定義RepositoryがGRDB実装になります。
    ///
    /// 責務: 正常な共有接続では利用不能実装にならない(失敗系の対照)ことを確認します。
    func testPIDDefinitionRepositoryIsGRDBWhenConnectionOpens() {
        let connection = ApplicationDatabaseConnection(openDatabaseQueue: { try DatabaseQueue() })

        let repository = MacOSApplicationComposition.makeOBDPIDDefinitionRepository(database: connection)

        XCTAssertTrue(repository is GRDBOBDPIDDefinitionRepository)
    }

    /// 開ける接続では車両別PID RepositoryがGRDB実装になります。
    ///
    /// 責務: 正常な共有接続では利用不能実装にならない(失敗系の対照)ことを確認します。
    func testVehiclePIDCapabilityRepositoryIsGRDBWhenConnectionOpens() {
        let connection = ApplicationDatabaseConnection(openDatabaseQueue: { try DatabaseQueue() })

        let repository = MacOSApplicationComposition.makeVehiclePIDCapabilityRepository(database: connection)

        XCTAssertTrue(repository is GRDBVehiclePIDCapabilityRepository)
    }
}
#endif
