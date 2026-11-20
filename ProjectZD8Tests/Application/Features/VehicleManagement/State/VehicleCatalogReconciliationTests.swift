import Foundation
import XCTest
@testable import ProjectZD8

/// 端末側の車両一覧と読込結果が、更新日時で正しく突き合わされることを検証します。
@MainActor
final class VehicleCatalogReconciliationTests: XCTestCase {
    /// 基準になる日時です。
    private let base = Date(timeIntervalSince1970: 1_000)

    /// 指定IDと更新日時の車両を生成します。
    ///
    /// 責務: 基準日時からの秒差で更新日時を決めた車両を1台作ります。
    /// - Parameters:
    ///   - id: 車両ID。
    ///   - name: 車両名(どちらの側の値か区別するため)。
    ///   - offset: 基準日時からの秒差。
    /// - Returns: 生成した車両。
    private func vehicle(_ id: VehicleID, _ name: String, at offset: TimeInterval) -> VehicleProfile {
        VehicleProfile(id: id, vin: "VIN-\(name)", name: name, updatedAt: base.addingTimeInterval(offset))
    }

    /// 両方が空なら、突き合わせ結果も空です。
    ///
    /// 責務: 空の一覧同士で、反映先とアップロード対象がともに空になることを確認します。
    func testEmptyLocalAndRemoteProducesEmptyResult() {
        let result = VehicleCatalogReconciliation(local: [], remote: [])
        XCTAssertEqual(result.merged, [])
        XCTAssertEqual(result.uploadTargets, [])
    }

    /// ローカルが空なら、読込結果が新しい順で採用され、アップロード対象はありません。
    ///
    /// 責務: 読込結果だけがある場合に、更新日時の新しい順の反映先になり、アップロードが不要であることを確認します。
    func testEmptyLocalAdoptsRemoteNewestFirstWithoutUpload() {
        let older = vehicle(VehicleID(), "older", at: 10)
        let newer = vehicle(VehicleID(), "newer", at: 20)
        let result = VehicleCatalogReconciliation(local: [], remote: [older, newer])
        XCTAssertEqual(result.merged.map(\.name), ["newer", "older"])
        XCTAssertEqual(result.uploadTargets, [])
    }

    /// 読込結果が空なら、ローカルの全車両が新しい順で残り、全てアップロード対象になります。
    ///
    /// 責務: 読込結果にない車両がすべて反映先に残り、アップロード対象になることを確認します。
    func testEmptyRemoteKeepsAllLocalAndUploadsAll() {
        let first = vehicle(VehicleID(), "first", at: 10)
        let second = vehicle(VehicleID(), "second", at: 20)
        let result = VehicleCatalogReconciliation(local: [first, second], remote: [])
        XCTAssertEqual(result.merged.map(\.name), ["second", "first"])
        XCTAssertEqual(result.uploadTargets.map(\.name), ["first", "second"])
    }

    /// 同じIDでローカルの更新日時が新しいなら、ローカルを採用してアップロードします。
    ///
    /// 責務: ローカルが新しい境界で、ローカルの内容が反映先とアップロード対象になることを確認します。
    func testNewerLocalWinsAndIsUploaded() {
        let id = VehicleID()
        let result = VehicleCatalogReconciliation(
            local: [vehicle(id, "local", at: 11)],
            remote: [vehicle(id, "remote", at: 10)]
        )
        XCTAssertEqual(result.merged.map(\.name), ["local"])
        XCTAssertEqual(result.uploadTargets.map(\.name), ["local"])
    }

    /// 同じIDで更新日時が同じなら、読込結果を採用し、アップロードしません。
    ///
    /// 責務: 更新日時が等しい境界で、読込結果が優先されアップロード対象にならないことを確認します。
    func testEqualTimestampPrefersRemoteWithoutUpload() {
        let id = VehicleID()
        let result = VehicleCatalogReconciliation(
            local: [vehicle(id, "local", at: 10)],
            remote: [vehicle(id, "remote", at: 10)]
        )
        XCTAssertEqual(result.merged.map(\.name), ["remote"])
        XCTAssertEqual(result.uploadTargets, [])
    }

    /// 同じIDでローカルの更新日時が古いなら、読込結果を採用し、アップロードしません。
    ///
    /// 責務: ローカルが古い場合に、読込結果の内容が反映先になることを確認します。
    func testOlderLocalLosesToRemoteWithoutUpload() {
        let id = VehicleID()
        let result = VehicleCatalogReconciliation(
            local: [vehicle(id, "local", at: 9)],
            remote: [vehicle(id, "remote", at: 10)]
        )
        XCTAssertEqual(result.merged.map(\.name), ["remote"])
        XCTAssertEqual(result.uploadTargets, [])
    }

    /// 読込結果にない車両は反映先に残りアップロードされ、ローカルにない車両は反映先へ加わるだけです。
    ///
    /// 責務: ローカルだけ・読込結果だけ・両方にある車両が混在する場合の反映先とアップロード対象を確認します。
    func testMixedVehiclesMergeAndUploadOnlyLocalWinners() {
        let sharedID = VehicleID()
        let localOnly = vehicle(VehicleID(), "localOnly", at: 30)
        let remoteOnly = vehicle(VehicleID(), "remoteOnly", at: 40)
        let result = VehicleCatalogReconciliation(
            local: [vehicle(sharedID, "sharedLocal", at: 20), localOnly],
            remote: [vehicle(sharedID, "sharedRemote", at: 10), remoteOnly]
        )
        XCTAssertEqual(result.merged.map(\.name), ["remoteOnly", "localOnly", "sharedLocal"])
        XCTAssertEqual(result.uploadTargets.map(\.name), ["sharedLocal", "localOnly"])
    }

    /// 反映先は、採用元にかかわらず更新日時の新しい順に並びます。
    ///
    /// 責務: ローカル採用と読込結果採用が混在しても、全体が更新日時の降順になることを確認します。
    func testMergedIsSortedByUpdatedAtDescendingAcrossSources() {
        let idA = VehicleID()
        let idB = VehicleID()
        let result = VehicleCatalogReconciliation(
            local: [vehicle(idA, "A", at: 5), vehicle(idB, "B", at: 50)],
            remote: [vehicle(idA, "A", at: 5), vehicle(idB, "B", at: 40), vehicle(VehicleID(), "C", at: 25)]
        )
        XCTAssertEqual(result.merged.map(\.name), ["B", "C", "A"])
    }
}
