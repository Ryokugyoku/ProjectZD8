import Foundation
import XCTest
@testable import ProjectZD8

/// iPhoneローカルRawログ除去前の安全判断を検証します。
final class ConnectionSessionLocalRemovalPolicyTests: XCTestCase {
    /// CloudKit保管済みの終了セッションはMac受領証なしでも安全に除去できます。
    ///
    /// 責務: CloudKit Raw Manifestをローカル除去の安全根拠として使用することを確認します。
    func testFinishedCloudStoredSessionWithoutMacReceiptIsSafe() {
        let session = makeSession(receiptDigest: nil)

        XCTAssertEqual(
            ConnectionSessionLocalRemovalPolicy().decision(for: session),
            .safe
        )
    }

    /// 現在Manifestと一致するMac受領証があれば安全な除去として扱います。
    ///
    /// 責務: Macへ検証済み取込済みのRawログを追加のデータ消失警告対象から除外します。
    func testMatchingMacReceiptAllowsSafeRemoval() {
        let session = makeSession(receiptDigest: "manifest")

        XCTAssertEqual(ConnectionSessionLocalRemovalPolicy().decision(for: session), .safe)
    }

    /// 古いMac受領証があっても現在のCloudKit Manifestを安全根拠にします。
    ///
    /// 責務: 廃止予定のMac受領証状態がCloudKit保管済み判断を妨げないことを確認します。
    func testMismatchedMacReceiptDoesNotOverrideCloudSafety() {
        let session = makeSession(receiptDigest: "old-manifest")

        XCTAssertEqual(
            ConnectionSessionLocalRemovalPolicy().decision(for: session),
            .safe
        )
    }

    /// CloudKit保管を確認できない終了済みRawログではデータ消失警告を要求します。
    ///
    /// 責務: 唯一のRawコピーを通常確認だけで除去させないことを確認します。
    func testCloudUploadFailureRequiresWarning() {
        var session = makeSession(receiptDigest: nil)
        session.rawLogSummary.cloudState = .failed
        session.rawLogSummary.manifestDigest = nil

        XCTAssertEqual(
            ConnectionSessionLocalRemovalPolicy().decision(for: session),
            .requiresDataLossWarning
        )
    }

    /// 取込受領証の条件を変えた終了済みセッションを生成します。
    ///
    /// 責務: 各テストへ同一のRawログ保有状態を供給します。
    /// - Parameter receiptDigest: 受領証へ設定するDigest。`nil` の場合は受領証を設定しません。
    /// - Returns: 除去判断が可能な完了済みセッション。
    private func makeSession(receiptDigest: String?) -> ConnectionSession {
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        session.endedAt = Date(timeIntervalSince1970: 101)
        session.endReason = .userDisconnected
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 1,
            byteCount: 2,
            localState: .available,
            cloudState: .uploaded,
            manifestDigest: "manifest",
            macImportReceipt: receiptDigest.map {
                ConnectionSessionMacImportReceipt(
                    deviceID: "mac",
                    deviceName: "Garage Mac",
                    importedAt: Date(timeIntervalSince1970: 102),
                    manifestDigest: $0
                )
            }
        )
        return session
    }
}
