import XCTest
@testable import ProjectZD8

/// `AuthenticationSessionRecheckPolicy` の待ち時間・上限回数・再確認すべき状態の判定を、境界と全段階で検証します。
///
/// 仕様: U5 受け入れ条件 15・17(5秒、15秒、60秒、以後60秒ごと、合計10回。確認できなかった時だけ再確認)。
final class AuthenticationSessionRecheckPolicyTests: XCTestCase {
    /// 既定の判定です。
    private let policy = AuthenticationSessionRecheckPolicy.standard

    /// 既定の待ち時間は 5・15・60 秒、以後60秒ごとで、合計10回です。
    ///
    /// 責務: 0〜9回目の待ち時間の列を仕様の値と突き合わせます。
    func testStandardDelaySequence() {
        let expected: [Duration] = [.seconds(5), .seconds(15), .seconds(60)] + Array(repeating: .seconds(60), count: 7)
        XCTAssertEqual((0..<10).map { policy.delay(beforeAttempt: $0) }, expected)
        XCTAssertEqual(policy.maximumAttempts, 10)
    }

    /// 上限の10回目(0始まりで9)までは待ち時間を返し、11回目(10)以降と負の回数は再確認しません。
    ///
    /// 責務: 9・10・11・-1 の境界を確認します。
    func testDelayBoundaries() {
        XCTAssertEqual(policy.delay(beforeAttempt: 9), .seconds(60))
        XCTAssertNil(policy.delay(beforeAttempt: 10))
        XCTAssertNil(policy.delay(beforeAttempt: 11))
        XCTAssertNil(policy.delay(beforeAttempt: -1))
    }

    /// 最初の数回の列より上限が短ければ、上限で打ち切ります。
    ///
    /// 責務: 列3件・上限2回で、2回目まで列の値、3回目は `nil` であることを確認します。
    func testMaximumShorterThanLeadingDelays() {
        let short = AuthenticationSessionRecheckPolicy(
            leadingDelays: [.seconds(1), .seconds(2), .seconds(3)], repeatingDelay: .seconds(9), maximumAttempts: 2
        )
        XCTAssertEqual(short.delay(beforeAttempt: 0), .seconds(1))
        XCTAssertEqual(short.delay(beforeAttempt: 1), .seconds(2))
        XCTAssertNil(short.delay(beforeAttempt: 2))
    }

    /// 上限0回では一度も再確認せず、最初の数回の列が空なら最初から繰り返しの待ち時間です。
    ///
    /// 責務: 上限0・列なしの分岐を確認します。
    func testZeroMaximumAndEmptyLeadingDelays() {
        XCTAssertNil(AuthenticationSessionRecheckPolicy(leadingDelays: [.seconds(1)], repeatingDelay: .seconds(2), maximumAttempts: 0)
            .delay(beforeAttempt: 0))
        let repeatingOnly = AuthenticationSessionRecheckPolicy(leadingDelays: [], repeatingDelay: .seconds(7), maximumAttempts: 1)
        XCTAssertEqual(repeatingOnly.delay(beforeAttempt: 0), .seconds(7))
        XCTAssertNil(repeatingOnly.delay(beforeAttempt: 1))
    }

    /// 負の待ち時間は0へ、負の上限は0(再確認しない)へ丸めます。
    ///
    /// 責務: 生成時の丸めを確認します。
    func testNegativeValuesAreClampedToZero() {
        let clamped = AuthenticationSessionRecheckPolicy(
            leadingDelays: [.seconds(-1)], repeatingDelay: .seconds(-5), maximumAttempts: -3
        )
        XCTAssertEqual(clamped.leadingDelays, [.zero])
        XCTAssertEqual(clamped.repeatingDelay, .zero)
        XCTAssertEqual(clamped.maximumAttempts, 0)
        XCTAssertNil(clamped.delay(beforeAttempt: 0))
    }

    /// 再確認するのは、サインアウト表示中で直近の確認が照会の失敗のまま解決していない時だけです。
    ///
    /// 責務: 4つの段階 × 未解決の有無の8通りを確認します(受け入れ条件 14・16)。
    func testShouldRecheckOnlyWhenSignedOutAndUnresolved() {
        let phases: [AuthenticationPhase] = [.checkingSession, .signedOut, .signingIn, .signedIn]
        for phase in phases {
            for unresolved in [false, true] {
                let expected = phase == .signedOut && unresolved
                XCTAssertEqual(policy.shouldRecheck(phase: phase, isSessionCheckUnresolved: unresolved), expected, "\(phase) \(unresolved)")
            }
        }
    }

    /// アカウント削除中(`.deletingAccount`)は、未解決の有無にかかわらず再確認しません。
    ///
    /// 責務: 削除中の段階で、未解決が true でも false でも再確認しないことを確認します。
    func testShouldNotRecheckWhileDeletingAccount() {
        for unresolved in [false, true] {
            XCTAssertFalse(policy.shouldRecheck(phase: .deletingAccount, isSessionCheckUnresolved: unresolved), "\(unresolved)")
        }
    }
}
