import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionRepository` のセッション状態遷移・削除系メソッドを分岐単位で検証します。
@MainActor
final class GRDBConnectionSessionRepositoryTransitionTests: XCTestCase {
    /// 検証用のMac受領証を返します。
    ///
    /// 責務: 指定Digestを持つ固定内容のMac取込受領証を生成します。
    /// - Parameter digest: 受領証が指すManifest Digest。
    /// - Returns: Mac取込受領証。
    private func receipt(digest: String) -> ConnectionSessionMacImportReceipt {
        ConnectionSessionMacImportReceipt(
            deviceID: "mac-installation",
            deviceName: "Garage Mac",
            importedAt: Date(timeIntervalSince1970: 500),
            manifestDigest: digest
        )
    }

    // MARK: - save

    /// 保存は既存の端末固有Raw概要を呼出し側の値で上書きしません。
    ///
    /// 責務: 概要を改ざんしたセッションを再保存しても保存済みRaw集計が維持されることを確認します。
    func testSavePreservesExistingRawLogSummary() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 2)
        var tampered = session
        tampered.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 99,
            byteCount: 999,
            localState: .removed,
            cloudState: .failed,
            manifestDigest: "tampered",
            macImportReceipt: nil
        )

        try fixtures.repository.save(tampered)

        let stored = try fixtures.storedRecord(session.id)
        XCTAssertEqual(stored.rawRecordCount, 2)
        XCTAssertEqual(stored.rawByteCount, 2)
        XCTAssertEqual(stored.localRawState, "available")
        XCTAssertEqual(stored.cloudSyncState, "pending")
        XCTAssertNil(stored.manifestDigest)
    }

    /// 保存済み行が復元不能な場合、保存は `integrityConflict` で失敗し行を変更しません。
    ///
    /// 責務: 既存行の読込失敗を握りつぶして上書きしないことを確認します。
    func testSaveThrowsIntegrityConflictWhenExistingRowIsInvalid() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = ConnectionSession(accountIdentifier: "account")
        try fixtures.repository.save(session)
        try fixtures.updateSessionRow("localRawState = 'corrupted'", id: session.id)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.save(session)
        }
        XCTAssertEqual(try fixtures.storedRecord(session.id).localRawState, "corrupted")
    }

    // MARK: - append

    /// 存在しないセッションへの追記は `invalidState` です。
    ///
    /// 責務: 不明セッションへRaw行を作らないことを確認します。
    func testAppendToUnknownSessionThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let unknown = ConnectionSessionID()

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.append(GRDBConnectionSessionRepositoryFixtures.observation(), to: unknown)
        }
        XCTAssertEqual(try fixtures.repository.entryCount(for: unknown), 0)
    }

    /// 終了済みセッションへの追記は `invalidState` で件数が増えません。
    ///
    /// 責務: 終了後のRaw追記を拒否することを確認します。
    func testAppendToEndedSessionThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 1)

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.append(GRDBConnectionSessionRepositoryFixtures.observation(), to: session.id)
        }
        XCTAssertEqual(try fixtures.repository.entryCount(for: session.id), 1)
    }

    // MARK: - deleteSession / deleteSessions

    /// 他アカウントによる単体削除は `invalidState` で、データを残します。
    ///
    /// 責務: 所有者不一致を具体エラーで拒否し、セッションと子Rawを保持することを確認します。
    func testDeleteSessionWithWrongAccountThrowsInvalidStateAndKeepsData() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 1, account: "account")

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.deleteSession(session.id, for: "other")
        }
        XCTAssertEqual(try fixtures.repository.sessions(for: "account").map(\.id), [session.id])
        XCTAssertEqual(try fixtures.repository.entryCount(for: session.id), 1)
    }

    /// 存在しないセッションの単体削除は `invalidState` です。
    ///
    /// 責務: 削除件数が1でない場合に失敗することを確認します。
    func testDeleteUnknownSessionThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.deleteSession(ConnectionSessionID(), for: "account")
        }
    }

    /// 該当セッションがないアカウントの一括削除は成功し、他アカウントを残します。
    ///
    /// 責務: 0件削除をエラーにせず、他アカウントのデータへ触れないことを確認します。
    func testDeleteSessionsForAccountWithoutSessionsKeepsOthers() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let retained = try fixtures.seedEndedSession(rawCount: 1, account: "retain")

        try fixtures.repository.deleteSessions(for: "nobody")

        XCTAssertEqual(try fixtures.repository.sessions(for: "retain").map(\.id), [retained.id])
        XCTAssertEqual(try fixtures.repository.entryCount(for: retained.id), 1)
    }

    // MARK: - markCloudUploaded

    /// アップロード済み記録は状態とDigestを設定し、既存のMac受領証を破棄します。
    ///
    /// 責務: 終了済みセッションの成功遷移と受領証の無効化を確認します。
    func testMarkCloudUploadedSetsStateAndClearsMacReceipt() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 1)
        try fixtures.repository.markCloudUploaded(sessionID: session.id, manifestDigest: "old")
        try fixtures.repository.markMacImported(receipt(digest: "old"), sessionID: session.id)

        try fixtures.repository.markCloudUploaded(sessionID: session.id, manifestDigest: "new")

        let stored = try fixtures.storedRecord(session.id)
        XCTAssertEqual(stored.cloudSyncState, "uploaded")
        XCTAssertEqual(stored.manifestDigest, "new")
        XCTAssertNil(stored.macImportedManifestDigest)
        XCTAssertNil(stored.macImportedDeviceID)
    }

    /// 不明セッションのアップロード記録は `invalidState` です。
    ///
    /// 責務: セッション不在の失敗を確認します。
    func testMarkCloudUploadedUnknownSessionThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.markCloudUploaded(sessionID: ConnectionSessionID(), manifestDigest: "digest")
        }
    }

    /// 未終了セッションのアップロード記録は `invalidState` で状態を変えません。
    ///
    /// 責務: 終了前のセッションをアップロード済みにしないことを確認します。
    func testMarkCloudUploadedOpenSessionThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = ConnectionSession(accountIdentifier: "account")
        try fixtures.repository.save(session)

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.markCloudUploaded(sessionID: session.id, manifestDigest: "digest")
        }
        XCTAssertEqual(try fixtures.storedRecord(session.id).cloudSyncState, "notUploaded")
    }

    /// 空Digestのアップロード記録は `invalidState` で状態を変えません。
    ///
    /// 責務: 空文字Digestと1文字Digestの境界を確認します。
    func testMarkCloudUploadedEmptyDigestThrowsInvalidStateButSingleCharacterSucceeds() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 0)

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.markCloudUploaded(sessionID: session.id, manifestDigest: "")
        }
        XCTAssertEqual(try fixtures.storedRecord(session.id).cloudSyncState, "notUploaded")

        try fixtures.repository.markCloudUploaded(sessionID: session.id, manifestDigest: "d")
        XCTAssertEqual(try fixtures.storedRecord(session.id).manifestDigest, "d")
    }

    // MARK: - markCloudUploadFailed

    /// ローカルRawがあるセッションは失敗状態へ遷移し、Digestなどは保持します。
    ///
    /// 責務: `available` からの成功遷移を確認します。
    func testMarkCloudUploadFailedSetsFailedForAvailableRaw() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 1)
        try fixtures.repository.markCloudUploaded(sessionID: session.id, manifestDigest: "digest")

        try fixtures.repository.markCloudUploadFailed(sessionID: session.id)

        let stored = try fixtures.storedRecord(session.id)
        XCTAssertEqual(stored.cloudSyncState, "failed")
        XCTAssertEqual(stored.localRawState, "available")
        XCTAssertEqual(stored.manifestDigest, "digest")
    }

    /// 不明セッションの失敗記録は `invalidState` です。
    ///
    /// 責務: セッション不在の失敗を確認します。
    func testMarkCloudUploadFailedUnknownSessionThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.markCloudUploadFailed(sessionID: ConnectionSessionID())
        }
    }

    /// Rawが `empty` または `removed` のセッションの失敗記録は `invalidState` です。
    ///
    /// 責務: ローカルRawを保有しないセッションを転送失敗にしないことを確認します。
    func testMarkCloudUploadFailedWithoutLocalRawThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let empty = try fixtures.seedEndedSession(rawCount: 0)
        let removed = try fixtures.seedEndedSession(rawCount: 1)
        try fixtures.repository.removeLocalEntries(for: removed.id)

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.markCloudUploadFailed(sessionID: empty.id)
        }
        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.markCloudUploadFailed(sessionID: removed.id)
        }
        XCTAssertEqual(try fixtures.storedRecord(empty.id).cloudSyncState, "notUploaded")
        XCTAssertEqual(try fixtures.storedRecord(removed.id).cloudSyncState, "pending")
    }

    // MARK: - markMacImported

    /// 同じDigestの受領証は保存されます。
    ///
    /// 責務: Digest一致時の受領証保存を確認します。
    func testMarkMacImportedStoresReceiptWhenDigestMatches() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 1)
        try fixtures.repository.markCloudUploaded(sessionID: session.id, manifestDigest: "digest")

        try fixtures.repository.markMacImported(receipt(digest: "digest"), sessionID: session.id)

        let loaded = try XCTUnwrap(fixtures.repository.sessions(for: "account").first)
        XCTAssertEqual(loaded.rawLogSummary.macImportReceipt, receipt(digest: "digest"))
        XCTAssertTrue(loaded.rawLogSummary.isDurablyImportedByMac)
    }

    /// 不明セッションへの受領証保存は `invalidState` です。
    ///
    /// 責務: セッション不在の失敗を確認します。
    func testMarkMacImportedUnknownSessionThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.markMacImported(receipt(digest: "digest"), sessionID: ConnectionSessionID())
        }
    }

    /// Digest不一致およびManifest未設定のセッションへの受領証保存は `integrityConflict` です。
    ///
    /// 責務: 別Manifestの受領証を関連付けないことを確認します。
    func testMarkMacImportedWithMismatchedOrMissingDigestThrowsIntegrityConflict() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let uploaded = try fixtures.seedEndedSession(rawCount: 1)
        let notUploaded = try fixtures.seedEndedSession(rawCount: 1)
        try fixtures.repository.markCloudUploaded(sessionID: uploaded.id, manifestDigest: "digest")

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.markMacImported(receipt(digest: "other"), sessionID: uploaded.id)
        }
        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.markMacImported(receipt(digest: "digest"), sessionID: notUploaded.id)
        }
        XCTAssertNil(try fixtures.storedRecord(uploaded.id).macImportedManifestDigest)
        XCTAssertNil(try fixtures.storedRecord(notUploaded.id).macImportedManifestDigest)
    }

    // MARK: - markRawLogAccessed

    /// `available` と `empty` のセッションは閲覧日時を保存できます。
    ///
    /// 責務: `removed` 以外で最終閲覧日時が更新されることを確認します。
    func testMarkRawLogAccessedStoresDateForAvailableAndEmptyRaw() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let available = try fixtures.seedEndedSession(rawCount: 1)
        let empty = try fixtures.seedEndedSession(rawCount: 0)
        let date = Date(timeIntervalSince1970: 777)

        try fixtures.repository.markRawLogAccessed(at: date, sessionID: available.id)
        try fixtures.repository.markRawLogAccessed(at: date, sessionID: empty.id)

        XCTAssertEqual(try fixtures.storedRecord(available.id).rawLastAccessedAt, date)
        XCTAssertEqual(try fixtures.storedRecord(empty.id).rawLastAccessedAt, date)
    }

    /// Rawが除去済みのセッションの閲覧記録は `invalidState` です。
    ///
    /// 責務: 存在しないローカルRawを閲覧済みにしないことを確認します。
    func testMarkRawLogAccessedRemovedRawThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 1)
        try fixtures.repository.removeLocalEntries(for: session.id)

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.markRawLogAccessed(at: Date(timeIntervalSince1970: 1), sessionID: session.id)
        }
        XCTAssertNil(try fixtures.storedRecord(session.id).rawLastAccessedAt)
    }

    /// 不明セッションの閲覧記録は `invalidState` です。
    ///
    /// 責務: セッション不在の失敗を確認します。
    func testMarkRawLogAccessedUnknownSessionThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.markRawLogAccessed(at: Date(), sessionID: ConnectionSessionID())
        }
    }

    /// 保存済み行が復元不能なセッションの更新は `integrityConflict` です。
    ///
    /// 責務: 更新系が壊れた行を読み込んだ場合に整合性エラーを返すことを確認します。
    func testUpdateOnInvalidStoredRowThrowsIntegrityConflict() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 1)
        try fixtures.updateSessionRow("cloudSyncState = 'corrupted'", id: session.id)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.markRawLogAccessed(at: Date(), sessionID: session.id)
        }
        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.repository.removeLocalEntries(for: session.id)
        }
    }

    // MARK: - removeLocalEntries

    /// 除去は対象セッションのRawだけを削除し、他セッションを保持します。
    ///
    /// 責務: 対象セッションの子行削除と `removed` 遷移、他セッションへの非干渉を確認します。
    func testRemoveLocalEntriesDeletesOnlyTargetSessionRaw() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let target = try fixtures.seedEndedSession(rawCount: 2)
        let other = try fixtures.seedEndedSession(rawCount: 2)

        try fixtures.repository.removeLocalEntries(for: target.id)

        XCTAssertEqual(try fixtures.repository.entryCount(for: target.id), 0)
        XCTAssertEqual(try fixtures.repository.entryCount(for: other.id), 2)
        XCTAssertEqual(try fixtures.storedRecord(target.id).localRawState, "removed")
        XCTAssertEqual(try fixtures.storedRecord(other.id).localRawState, "available")
    }

    /// 不明セッションの除去は `invalidState` です。
    ///
    /// 責務: セッション不在の失敗を確認します。
    func testRemoveLocalEntriesUnknownSessionThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.removeLocalEntries(for: ConnectionSessionID())
        }
    }

    /// 未終了セッションのRaw除去は `invalidState` でRawを残します。
    ///
    /// 責務: 取得中のRawを消さないことを確認します。
    func testRemoveLocalEntriesOpenSessionThrowsInvalidStateAndKeepsRaw() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = ConnectionSession(accountIdentifier: "account")
        try fixtures.repository.save(session)
        try fixtures.repository.append(GRDBConnectionSessionRepositoryFixtures.observation(), to: session.id)

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.removeLocalEntries(for: session.id)
        }
        XCTAssertEqual(try fixtures.repository.entryCount(for: session.id), 1)
    }

    /// Rawが `empty` または既に `removed` のセッションの除去は `invalidState` です。
    ///
    /// 責務: `available` 以外の保管状態からは除去できないことを確認します。
    func testRemoveLocalEntriesWithoutAvailableRawThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let empty = try fixtures.seedEndedSession(rawCount: 0)
        let removed = try fixtures.seedEndedSession(rawCount: 1)
        try fixtures.repository.removeLocalEntries(for: removed.id)

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.removeLocalEntries(for: empty.id)
        }
        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.repository.removeLocalEntries(for: removed.id)
        }
        XCTAssertEqual(try fixtures.storedRecord(empty.id).localRawState, "empty")
        XCTAssertEqual(try fixtures.storedRecord(removed.id).localRawState, "removed")
    }
}
