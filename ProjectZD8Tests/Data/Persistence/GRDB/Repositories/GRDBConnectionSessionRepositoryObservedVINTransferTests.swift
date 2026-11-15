import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionRepository.importCloudMetadata` における観測VINの補完と整合判定を検証します。
@MainActor
final class GRDBConnectionSessionRepositoryObservedVINTransferTests: XCTestCase {
    /// 代表VINです。
    private static let vin = "JF1ZD8ABC12345678"

    /// 観測VINを指定した終了済みセッションを保存します。
    ///
    /// 責務: 既存セッションとして1件の終了済みセッションを実Repository経由で保存します。
    /// - Parameters:
    ///   - fixtures: 保存先。
    ///   - observedVIN: ローカル側の観測VIN。
    /// - Returns: 保存したセッション。
    /// - Throws: 保存の失敗。
    private func saveLocal(_ fixtures: GRDBConnectionSessionRepositoryFixtures, observedVIN: String?) throws -> ConnectionSession {
        var session = GRDBConnectionSessionRepositoryFixtures.endedSession()
        session.observedVIN = observedVIN
        try fixtures.repository.save(session)
        return session
    }

    /// 同じIDで観測VINだけを差し替えた転送側概要を作ります。
    ///
    /// 責務: 観測VIN以外はローカルと同じ内容の1件のCloudKit概要を返します。
    /// - Parameters:
    ///   - local: ローカル側セッション。
    ///   - observedVIN: 転送側の観測VIN。
    /// - Returns: 取込対象の概要。
    private func transferred(_ local: ConnectionSession, observedVIN: String?) -> ConnectionSessionCloudMetadata {
        var copy = local
        copy.observedVIN = observedVIN
        return ConnectionSessionCloudMetadata(session: copy, manifestDigest: "digest")
    }

    /// ローカルに観測VINが無く転送側にある場合は転送値で補完されます。
    ///
    /// 責務: 欠落中の観測VINが取込で非破壊に埋まることを確認します。
    func testImportFillsMissingLocalObservedVINFromTransfer() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let local = try saveLocal(fixtures, observedVIN: nil)

        try fixtures.repository.importCloudMetadata(transferred(local, observedVIN: Self.vin))

        XCTAssertEqual(try fixtures.storedRecord(local.id).observedVIN, Self.vin)
        XCTAssertEqual(try fixtures.storedRecord(local.id).manifestDigest, "digest")
    }

    /// ローカルにだけ観測VINがあり転送側に無い場合は整合し、ローカル値が残ります。
    ///
    /// 責務: 片側欠落の観測VINが不整合扱いにも消去にもならないことを確認します。
    func testImportKeepsLocalObservedVINWhenTransferLacksIt() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let local = try saveLocal(fixtures, observedVIN: Self.vin)

        try fixtures.repository.importCloudMetadata(transferred(local, observedVIN: nil))

        XCTAssertEqual(try fixtures.storedRecord(local.id).observedVIN, Self.vin)
        XCTAssertEqual(try fixtures.storedRecord(local.id).manifestDigest, "digest")
    }

    /// 両方にあって大文字小文字だけが異なる観測VINは整合として取り込まれ、ローカル値が残ります。
    ///
    /// 責務: 大文字小文字の違いを不整合とせず、既存値を上書きしないことを確認します。
    func testImportTreatsCaseOnlyDifferenceAsCompatible() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let local = try saveLocal(fixtures, observedVIN: Self.vin)

        try fixtures.repository.importCloudMetadata(transferred(local, observedVIN: Self.vin.lowercased()))

        let stored = try fixtures.storedRecord(local.id)
        XCTAssertEqual(stored.observedVIN, Self.vin)
        XCTAssertEqual(stored.manifestDigest, "digest")
        XCTAssertEqual(stored.cloudSyncState, "uploaded")
    }

    /// 異なる観測VINは既存の不整合と同じ `integrityConflict` になり、保存済み行は変わりません。
    ///
    /// 責務: 別VINの取込が拒否され、観測VIN・Digest・同期状態が取込前のまま残ることを確認します。
    func testImportRejectsDifferentObservedVINAsIntegrityConflict() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let local = try saveLocal(fixtures, observedVIN: Self.vin)
        let before = try fixtures.storedRecord(local.id)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.importCloudMetadata(self.transferred(local, observedVIN: "JF1ZD8XYZ87654321"))
        }

        let after = try fixtures.storedRecord(local.id)
        XCTAssertEqual(after.observedVIN, Self.vin)
        XCTAssertEqual(after.manifestDigest, before.manifestDigest)
        XCTAssertEqual(after.cloudSyncState, before.cloudSyncState)
    }
}
