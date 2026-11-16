import Foundation
import XCTest
@testable import ProjectZD8

/// `AdapterLinkRecordingIntentPolicy` の[記録開始]の扱い方・処理できない理由・有効期限の判定を、全状態と境界で検証します。
///
/// 仕様: U4 受け入れ条件 5・7・9・10。有効期限は選択から2分(ちょうど2分は有効)。
@MainActor
final class AdapterLinkRecordingIntentPolicyTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 検証対象の方針(既定の有効期限)です。
    private let policy = AdapterLinkRecordingIntentPolicy()

    /// 仕様の有効期限(2分)の秒数です。
    private let lifetime: TimeInterval = 120

    /// 意思として保持され得る状態(待機・初期化中・確認中・VIN読取中)です。
    private var intentCandidateStates: [AdapterLinkSupervisionState] {
        Array(F.allStates[0...4])
    }

    /// 状態機械へそのまま渡す状態(検知待ち・記録中・終了処理中・抑止中)です。
    private var forwardedStates: [AdapterLinkSupervisionState] {
        [F.allStates[5], F.allStates[6], .finishing, .heldAfterUserStop(.awaitingStart), F.watching()]
    }

    /// 既定の有効期限は2分です。
    ///
    /// 責務: `standardLifetime` と既定生成の `lifetime` が120秒であることを確認します(受け入れ条件 5)。
    func testStandardLifetimeIsTwoMinutes() {
        XCTAssertEqual(AdapterLinkRecordingIntentPolicy.standardLifetime, lifetime)
        XCTAssertEqual(policy.lifetime, lifetime)
        XCTAssertEqual(AdapterLinkRecordingIntentPolicy(lifetime: 30).lifetime, 30)
    }

    /// 検知待ち・記録中・終了処理中・抑止中に届いた選択は、条件によらず状態機械へ渡します。
    ///
    /// 責務: 稼働条件を満たす・満たさないどちらでも `.forwardToTransition` になることを確認します(受け入れ条件 9)。
    func testForwardedStatesAlwaysGoToTransition() {
        let conditionsList = [F.conditions(), F.conditions(isSupervisionStarted: false), F.conditions(isSignedIn: false)]
        for state in forwardedStates {
            for conditions in conditionsList {
                XCTAssertEqual(policy.disposition(for: state, conditions: conditions), .forwardToTransition, "\(state)")
            }
        }
    }

    /// 待機・初期化中・確認中・VIN読取中に届いた選択は、処理できる条件なら意思として保持します。
    ///
    /// 責務: 稼働中・サインイン済み・既定BLEありで `.keepAsIntent` になることを確認します(受け入れ条件 5)。
    func testCandidateStatesKeepIntentWhenOperating() {
        for state in intentCandidateStates {
            XCTAssertEqual(policy.disposition(for: state, conditions: F.conditions()), .keepAsIntent, "\(state)")
        }
    }

    /// 待機・初期化中・確認中・VIN読取中に届いた選択は、処理できない条件なら理由つきで捨てます。
    ///
    /// 責務: 監視停止・未サインイン・既定アダプターなし・既定がBLE以外で、それぞれの理由の `.reject` になることを確認します(受け入れ条件 7)。
    func testCandidateStatesRejectWithReasonWhenNotOperating() {
        let cases: [(AdapterLinkSupervisionConditions, AdapterLinkRecordingStartFailureReason)] = [
            (F.conditions(isSupervisionStarted: false), .vehicleNotDetected),
            (F.conditions(isSignedIn: false), .signInRequired),
            (F.conditions(defaultAdapterPreference: nil), .adapterNotConfigured),
            (F.conditions(defaultAdapterPreference: F.classicPreference), .adapterNotConfigured),
            (F.conditions(defaultAdapterPreference: F.serialPreference), .adapterNotConfigured),
        ]
        for state in intentCandidateStates {
            for (conditions, reason) in cases {
                XCTAssertEqual(policy.disposition(for: state, conditions: conditions), .reject(reason), "\(state) / \(reason)")
            }
        }
    }

    /// 処理できない理由は、監視停止 → 未サインイン → 既定アダプターなしの順に選びます。
    ///
    /// 責務: 複数の条件が重なった時に先の理由が選ばれ、全て満たせば `nil` になることを確認します(受け入れ条件 7・10)。
    func testRejectionReasonOrder() {
        XCTAssertNil(policy.rejectionReason(F.conditions()))
        XCTAssertEqual(
            policy.rejectionReason(F.conditions(isSupervisionStarted: false, isSignedIn: false, defaultAdapterPreference: nil)),
            .vehicleNotDetected
        )
        XCTAssertEqual(policy.rejectionReason(F.conditions(isSignedIn: false, defaultAdapterPreference: nil)), .signInRequired)
        XCTAssertEqual(policy.rejectionReason(F.conditions(defaultAdapterPreference: nil)), .adapterNotConfigured)
    }

    /// リンクの状態・リンクの接続対象は処理できるかどうかに関係しません。
    ///
    /// 責務: リンク未開始・切断中でも稼働条件を満たせば `nil` であることを確認します(リンクを待つのが意思の役目のため)。
    func testRejectionReasonIgnoresLinkState() {
        XCTAssertNil(policy.rejectionReason(F.conditions(linkPreference: nil, linkState: .idle)))
        XCTAssertNil(policy.rejectionReason(F.conditions(linkState: .disconnected(.peripheralDisconnected(errorDescription: nil)))))
    }

    /// 有効期限の直前・ちょうど2分は有効、直後は無効です。
    ///
    /// 責務: 選択から 0・119.999・120 秒は `true`、120.001 秒は `false` であることを確認します(受け入れ条件 10 の境界)。
    func testIsValidBoundaries() {
        let intent = AdapterLinkRecordingIntent(selectedAt: F.referenceDate)
        XCTAssertTrue(policy.isValid(intent, now: F.referenceDate))
        XCTAssertTrue(policy.isValid(intent, now: F.date(lifetime - 0.001)), "直前")
        XCTAssertTrue(policy.isValid(intent, now: F.date(lifetime)), "ちょうど")
        XCTAssertFalse(policy.isValid(intent, now: F.date(lifetime + 0.001)), "直後")
    }

    /// 注入した有効期限で判定します。
    ///
    /// 責務: 有効期限30秒の方針で、30秒は有効・30.001秒は無効であることを確認します。
    func testIsValidUsesInjectedLifetime() {
        let custom = AdapterLinkRecordingIntentPolicy(lifetime: 30)
        let intent = AdapterLinkRecordingIntent(selectedAt: F.referenceDate)
        XCTAssertTrue(custom.isValid(intent, now: F.date(30)))
        XCTAssertFalse(custom.isValid(intent, now: F.date(30.001)))
    }

    /// 期限の満了を確かめる待ちは、ちょうど2分(有効)を超えた最初の時点です。
    ///
    /// 責務: 既定で 120.001 秒、30秒の方針で 30.001 秒であり、その時点で意思が無効と判定されることを確認します。
    func testExpiryCheckDelayIsJustAfterLifetime() {
        XCTAssertEqual(policy.expiryCheckDelay, .milliseconds(120_001))
        XCTAssertEqual(AdapterLinkRecordingIntentPolicy(lifetime: 30).expiryCheckDelay, .milliseconds(30_001))
        let intent = AdapterLinkRecordingIntent(selectedAt: F.referenceDate)
        XCTAssertFalse(policy.isValid(intent, now: F.date(120.001)))
    }
}
