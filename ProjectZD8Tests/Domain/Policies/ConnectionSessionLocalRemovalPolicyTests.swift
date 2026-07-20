import Foundation
import XCTest
@testable import ProjectZD8

/// iPhoneローカルRawログ除去前の安全判断を検証します。
final class ConnectionSessionLocalRemovalPolicyTests: XCTestCase {
    /// Mac取込証跡がない終了済みセッションではデータ消失警告を要求します。
    ///
    /// 責務: 未取込の可能性があるRawログを標準確認だけで除去させないことを確認します。
    func testFinishedSessionWithoutMacReceiptRequiresWarning() {
        let session = makeSession(receiptDigest: nil)

        XCTAssertEqual(
            ConnectionSessionLocalRemovalPolicy().decision(for: session),
            .requiresDataLossWarning
        )
    }

    /// 現在Manifestと一致するMac受領証があれば安全な除去として扱います。
    ///
    /// 責務: Macへ検証済み取込済みのRawログを追加のデータ消失警告対象から除外します。
    func testMatchingMacReceiptAllowsSafeRemoval() {
        let session = makeSession(receiptDigest: "manifest")

        XCTAssertEqual(ConnectionSessionLocalRemovalPolicy().decision(for: session), .safe)
    }

    /// 古いManifestのMac受領証は未取込と同じ警告対象です。
    ///
    /// 責務: 現在Payloadと一致しないMac受領証を安全根拠として使用しないことを確認します。
    func testMismatchedMacReceiptRequiresWarning() {
        let session = makeSession(receiptDigest: "old-manifest")

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
