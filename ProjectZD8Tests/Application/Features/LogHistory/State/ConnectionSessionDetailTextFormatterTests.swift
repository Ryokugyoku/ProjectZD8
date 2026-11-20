import Foundation
import XCTest
@testable import ProjectZD8

/// 接続セッション詳細画面の判定・文言・ローカライズキー選択を検証します。
@MainActor
final class ConnectionSessionDetailTextFormatterTests: XCTestCase {
    /// 検証対象の詳細画面向け整形です。
    private let formatter = ConnectionSessionDetailTextFormatter()

    /// 取得元端末があれば `名前 (プラットフォーム)` を返します。
    ///
    /// 責務: 全プラットフォームの端末表示を確認します。
    func testAcquisitionDeviceTextIncludesNameAndPlatform() {
        let cases: [(ConnectionSessionAcquisitionPlatform, String)] = [
            (.iPhone, "Ryo (iPhone)"), (.iPad, "Ryo (iPad)"), (.macOS, "Ryo (macOS)")
        ]
        for (platform, expected) in cases {
            let session = makeSession(device: ConnectionSessionAcquisitionDevice(platform: platform, name: "Ryo"))

            XCTAssertEqual(formatter.acquisitionDeviceText(session), expected)
        }
    }

    /// 取得元端末が無い旧履歴は不明文言です。
    ///
    /// 責務: 端末 nil のときの `history.device.unknown` を確認します。
    func testAcquisitionDeviceTextFallsBackToUnknown() {
        XCTAssertEqual(formatter.acquisitionDeviceText(makeSession()), String(localized: "history.device.unknown"))
    }

    /// 車両無応答だけが専用の本文キーになります。
    ///
    /// 責務: 終了理由ごとの停止確認カード本文キーを確認します。
    func testStopReviewMessageKeyDependsOnEndReason() {
        XCTAssertEqual(
            formatter.stopReviewMessageKey(makeSession(endReason: .vehicleNoResponse)),
            "history.stop_review.card.no_response"
        )
        let others: [ConnectionSessionEndReason?] = [
            .connectionLost, .userDisconnected, .acquisitionFailed, .superseded,
            .accountSignedOut, .unexpectedTermination, nil
        ]
        for reason in others {
            XCTAssertEqual(
                formatter.stopReviewMessageKey(makeSession(endReason: reason)),
                "history.stop_review.card.connection_lost"
            )
        }
    }

    /// 容量はファイル形式で整形し、負の値は0として扱います。
    ///
    /// 責務: 0、正の値、負の値、最小値の容量文字列を確認します。
    func testByteCountTextUsesFileStyleAndClampsNegative() {
        let zero = ByteCountFormatter.string(fromByteCount: 0, countStyle: .file)

        XCTAssertEqual(formatter.byteCountText(0), zero)
        XCTAssertEqual(formatter.byteCountText(-1), zero)
        XCTAssertEqual(formatter.byteCountText(Int64.min), zero)
        XCTAssertEqual(
            formatter.byteCountText(1_500_000),
            ByteCountFormatter.string(fromByteCount: 1_500_000, countStyle: .file)
        )
        XCTAssertNotEqual(formatter.byteCountText(1_500_000), zero)
    }

    /// 正式データ判定の5分岐です。
    ///
    /// 責務: 接続中・要確認・ユーザー承認済み・正式・中断の文言を確認します。
    func testDispositionTextCoversAllFiveBranches() {
        let cases: [(ConnectionSession, String)] = [
            (makeSession(endReason: nil), "history.status.connected"),
            (makeSession(endReason: .vehicleNoResponse), "history.detail.disposition.review"),
            (makeSession(endReason: .connectionLost), "history.detail.disposition.review"),
            (makeSession(endReason: .connectionLost, decision: .userInitiated), "history.detail.disposition.user_accepted"),
            (makeSession(endReason: .vehicleNoResponse, decision: .userInitiated), "history.detail.disposition.user_accepted"),
            (makeSession(endReason: .userDisconnected), "history.detail.disposition.regular"),
            (makeSession(endReason: .acquisitionFailed), "history.status.interrupted"),
            (makeSession(endReason: .superseded), "history.status.interrupted"),
            (makeSession(endReason: .accountSignedOut), "history.status.interrupted"),
            (makeSession(endReason: .unexpectedTermination), "history.status.interrupted")
        ]
        for (session, key) in cases {
            XCTAssertEqual(formatter.dispositionText(session), String(localized: String.LocalizationValue(key)), key)
        }
    }

    /// 接続中は承認済みの判断があっても接続中の文言です。
    ///
    /// 責務: 判定の優先順位(接続中が最優先)を確認します。
    func testDispositionTextPrefersConnectedOverDecision() {
        let session = makeSession(endReason: nil, decision: .userInitiated)

        XCTAssertEqual(formatter.dispositionText(session), String(localized: "history.status.connected"))
    }

    /// 終了理由が無ければ `—`、あれば固定キーの文言です。
    ///
    /// 責務: 全終了理由と nil の表示を確認します。
    func testObservedEndReasonText() {
        XCTAssertEqual(formatter.observedEndReasonText(makeSession(endReason: nil)), "—")
        let keys: [(ConnectionSessionEndReason, String)] = [
            (.userDisconnected, "history.reason.userDisconnected"),
            (.vehicleNoResponse, "history.reason.vehicleNoResponse"),
            (.connectionLost, "history.reason.connectionLost"),
            (.acquisitionFailed, "history.reason.acquisitionFailed"),
            (.superseded, "history.reason.superseded"),
            (.accountSignedOut, "history.reason.accountSignedOut"),
            (.unexpectedTermination, "history.reason.unexpectedTermination")
        ]
        for (reason, key) in keys {
            XCTAssertEqual(
                formatter.observedEndReasonText(makeSession(endReason: reason)),
                String(localized: String.LocalizationValue(key))
            )
        }
    }

    /// 状態キーは接続中・完了・中断の3種です。
    ///
    /// 責務: 3状態と、承認済みで完了になる経路のキーを確認します。
    func testSessionStatusKey() {
        XCTAssertEqual(formatter.sessionStatusKey(makeSession(endReason: nil)), "history.status.connected")
        XCTAssertEqual(formatter.sessionStatusKey(makeSession(endReason: .userDisconnected)), "history.status.completed")
        XCTAssertEqual(
            formatter.sessionStatusKey(makeSession(endReason: .connectionLost, decision: .userInitiated)),
            "history.status.completed"
        )
        XCTAssertEqual(formatter.sessionStatusKey(makeSession(endReason: .connectionLost)), "history.status.interrupted")
        XCTAssertEqual(formatter.sessionStatusKey(makeSession(endReason: .acquisitionFailed)), "history.status.interrupted")
    }

    /// 4条件がすべて揃った時だけ学習へ使えます。
    ///
    /// 責務: 全条件が真の場合に true になることを確認します。
    func testIsTrainingReadyWhenAllConditionsHold() {
        XCTAssertTrue(formatter.isTrainingReady(makeReadySession()))
    }

    /// 車両が無ければ学習へ使えません。
    ///
    /// 責務: 車両条件の欠落を確認します。
    func testIsTrainingReadyRequiresVehicle() {
        var session = makeReadySession()
        session.vehicle = nil

        XCTAssertFalse(formatter.isTrainingReady(session))
    }

    /// ローカルRawが available 以外なら学習へ使えません。
    ///
    /// 責務: 保管状態 empty / removed の欠落を確認します。
    func testIsTrainingReadyRequiresAvailableLocalState() {
        for state in [ConnectionSessionLocalRawState.empty, .removed] {
            var session = makeReadySession()
            session.rawLogSummary.localState = state

            XCTAssertFalse(formatter.isTrainingReady(session))
        }
    }

    /// 記録件数は1件以上が必要で、0件は不可です。
    ///
    /// 責務: 件数の境界(0 と 1)を確認します。
    func testIsTrainingReadyRequiresPositiveRecordCount() {
        var session = makeReadySession()
        session.rawLogSummary.recordCount = 0
        XCTAssertFalse(formatter.isTrainingReady(session))
        session.rawLogSummary.recordCount = 1
        XCTAssertTrue(formatter.isTrainingReady(session))
    }

    /// Mac の取り込み完了が確認できなければ学習へ使えません。
    ///
    /// 責務: 受領証なし、ダイジェスト不一致、ダイジェストなしの欠落を確認します。
    func testIsTrainingReadyRequiresDurableMacImport() {
        var noReceipt = makeReadySession()
        noReceipt.rawLogSummary.macImportReceipt = nil
        var mismatch = makeReadySession()
        mismatch.rawLogSummary.macImportReceipt = makeReceipt(digest: "other")
        var noDigest = makeReadySession()
        noDigest.rawLogSummary.manifestDigest = nil

        XCTAssertFalse(formatter.isTrainingReady(noReceipt))
        XCTAssertFalse(formatter.isTrainingReady(mismatch))
        XCTAssertFalse(formatter.isTrainingReady(noDigest))
    }

    /// 解析カードの補足は記録件数を含みます。
    ///
    /// 責務: 0件と複数件で `analysis.card.caption` に件数が入ることを確認します。
    func testAnalysisCardCaptionEmbedsRecordCount() {
        for count in [Int64(0), 42] {
            var session = makeSession()
            session.rawLogSummary.recordCount = count
            let expected = String(
                format: String(localized: "analysis.card.caption"),
                locale: .autoupdatingCurrent,
                count
            )

            XCTAssertEqual(formatter.analysisCardCaption(session), expected)
            XCTAssertTrue(formatter.analysisCardCaption(session).contains("\(count)"))
        }
    }

    /// 検証用のセッションを作ります。
    ///
    /// 責務: 終了理由・判断・取得端末を指定した未保存のセッションを返します。
    /// - Parameters:
    ///   - endReason: 終了理由。
    ///   - decision: 停止確認の判断。
    ///   - device: 取得元端末。
    /// - Returns: 検証用セッション。
    private func makeSession(
        endReason: ConnectionSessionEndReason? = nil,
        decision: ConnectionSessionStopReviewDecision? = nil,
        device: ConnectionSessionAcquisitionDevice? = nil
    ) -> ConnectionSession {
        var session = ConnectionSession(accountIdentifier: "account", acquisitionDevice: device)
        session.endReason = endReason
        session.stopReviewDecision = decision
        return session
    }

    /// 学習へ使える条件が揃ったセッションを作ります。
    ///
    /// 責務: 車両・available・1件以上・Mac取込済みを満たすセッションを返します。
    /// - Returns: 学習準備完了のセッション。
    private func makeReadySession() -> ConnectionSession {
        var session = makeSession(endReason: .userDisconnected)
        session.vehicle = ConnectionSessionVehicle(id: VehicleID(), name: "ZD8", displayIdentifier: "JF1ZD8")
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 10,
            byteCount: 100,
            localState: .available,
            cloudState: .uploaded,
            manifestDigest: "digest",
            macImportReceipt: makeReceipt(digest: "digest")
        )
        return session
    }

    /// 検証用のMac取込受領証を作ります。
    ///
    /// 責務: ダイジェストを指定した受領証を返します。
    /// - Parameter digest: 受領証のマニフェストダイジェスト。
    /// - Returns: 検証用受領証。
    private func makeReceipt(digest: String) -> ConnectionSessionMacImportReceipt {
        ConnectionSessionMacImportReceipt(
            deviceID: "mac", deviceName: "Mac", importedAt: Date(timeIntervalSince1970: 1), manifestDigest: digest
        )
    }
}
