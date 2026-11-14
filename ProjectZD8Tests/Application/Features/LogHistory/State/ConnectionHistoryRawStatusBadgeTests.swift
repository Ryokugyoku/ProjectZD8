import XCTest
@testable import ProjectZD8

/// Raw保管状態バッジの表示変換を検証します。
@MainActor
final class ConnectionHistoryRawStatusBadgeTests: XCTestCase {
    /// 指定値をそのまま保持します。
    ///
    /// 責務: 基本イニシャライザが3値を保持することを確認します。
    func testMemberwiseInitializerKeepsValues() {
        let badge = ConnectionHistoryRawStatusBadge(titleKey: "key", systemImage: "symbol", tone: .critical)

        XCTAssertEqual(badge.titleKey, "key")
        XCTAssertEqual(badge.systemImage, "symbol")
        XCTAssertEqual(badge.tone, .critical)
    }

    /// CloudKit転送状態の全ケースが従来の文言、シンボル、色調へ対応します。
    ///
    /// 責務: 未アップロード、待機、保存済み、失敗の4ケースを確認します。
    func testCloudStateBadgesMatchListPresentation() {
        let cases: [(ConnectionSessionCloudSyncState, ConnectionHistoryRawStatusBadge)] = [
            (.notUploaded, .init(titleKey: "history.raw.cloud.not_uploaded", systemImage: "icloud.slash", tone: .neutral)),
            (.pending, .init(titleKey: "history.raw.cloud.pending", systemImage: "icloud.and.arrow.up", tone: .caution)),
            (.uploaded, .init(titleKey: "history.raw.cloud.uploaded", systemImage: "checkmark.icloud.fill", tone: .positive)),
            (.failed, .init(titleKey: "history.raw.cloud.failed", systemImage: "exclamationmark.icloud.fill", tone: .critical))
        ]
        for (state, expected) in cases {
            XCTAssertEqual(ConnectionHistoryRawStatusBadge(cloudState: state), expected, "\(state)")
        }
    }

    /// ローカルRaw状態の全ケースが従来の文言、シンボル、色調へ対応します。
    ///
    /// 責務: 未記録、保存済み、除去済みの3ケースを確認します。
    func testLocalStateBadgesMatchListPresentation() {
        let cases: [(ConnectionSessionLocalRawState, ConnectionHistoryRawStatusBadge)] = [
            (.empty, .init(titleKey: "history.raw.local.empty", systemImage: "minus.circle", tone: .neutral)),
            (.available, .init(titleKey: "history.raw.local.available", systemImage: "checkmark.circle.fill", tone: .informative)),
            (.removed, .init(titleKey: "history.raw.local.removed", systemImage: "icloud.and.arrow.down", tone: .neutral))
        ]
        for (state, expected) in cases {
            XCTAssertEqual(ConnectionHistoryRawStatusBadge(localState: state), expected, "\(state)")
        }
    }

    /// 色調は従来の5色に1対1で対応する5ケースです。
    ///
    /// 責務: 色調 enum のケース構成を固定します。
    func testStatusToneHasFiveCases() {
        XCTAssertEqual(ConnectionHistoryStatusTone.allCases, [.neutral, .caution, .positive, .critical, .informative])
    }
}
