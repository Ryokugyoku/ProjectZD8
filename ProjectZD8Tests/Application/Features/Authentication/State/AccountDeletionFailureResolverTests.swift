import XCTest
@testable import ProjectZD8

/// `AccountDeletionFailureResolver` が、削除中のエラーを表示する失敗の原因へ決める順序を検証します。
///
/// 仕様: 記録の終了待ちのタイムアウトは `.acquisitionTimedOut`。それ以外は分類境界に委ね、境界が無ければ `.deletionFailed`。
final class AccountDeletionFailureResolverTests: XCTestCase {
    /// 検証用の任意のエラーです。
    private struct OtherError: Error {}

    /// 呼び出しを記録し、固定の原因を返す分類境界です。
    private final class ClassifierSpy: AccountDeletionFailureClassifying {
        /// 返す原因です。
        let result: AccountDeletionFailure
        /// 分類を求められた回数です。
        private(set) var callCount = 0

        /// 返す原因を指定して生成します。
        ///
        /// 責務: 分類結果を固定します。
        /// - Parameter result: 返す原因。
        init(result: AccountDeletionFailure) { self.result = result }

        /// 固定の原因を返します。
        ///
        /// 責務: 呼び出しを数えて固定の原因を返します。
        /// - Parameter error: 使用しないエラー。
        /// - Returns: 固定の原因。
        func failure(for _: Error) -> AccountDeletionFailure {
            callCount += 1
            return result
        }
    }

    /// 記録の終了待ちのタイムアウトは、分類境界があっても `.acquisitionTimedOut` になることを検証します。
    ///
    /// 責務: タイムアウトが分類境界より先に判定され、境界を呼ばないことを確認します。
    func testTimedOutResolvesToAcquisitionTimedOutBeforeClassifier() {
        let classifier = ClassifierSpy(result: .networkUnavailable)

        let failure = AccountDeletionFailureResolver(classifier: classifier)
            .failure(for: AccountDeletionAcquisitionDrainError.timedOut)

        XCTAssertEqual(failure, .acquisitionTimedOut)
        XCTAssertEqual(classifier.callCount, 0)
    }

    /// 分類境界が無くてもタイムアウトは `.acquisitionTimedOut` になることを検証します。
    ///
    /// 責務: 境界未設定でもタイムアウトの判定が働くことを確認します。
    func testTimedOutResolvesWithoutClassifier() {
        XCTAssertEqual(
            AccountDeletionFailureResolver().failure(for: AccountDeletionAcquisitionDrainError.timedOut),
            .acquisitionTimedOut
        )
    }

    /// タイムアウト以外のエラーは、分類境界の結果をそのまま返すことを検証します。
    ///
    /// 責務: 各原因を返す境界について、結果が素通しされ1回だけ呼ばれることを確認します。
    func testOtherErrorsDelegateToClassifier() {
        let causes: [AccountDeletionFailure] = [.iCloudUnavailable, .networkUnavailable, .serviceBusy, .acquisitionTimedOut, .deletionFailed]
        for cause in causes {
            let classifier = ClassifierSpy(result: cause)

            let failure = AccountDeletionFailureResolver(classifier: classifier).failure(for: OtherError())

            XCTAssertEqual(failure, cause)
            XCTAssertEqual(classifier.callCount, 1, "\(cause)")
        }
    }

    /// 分類境界が無ければ、タイムアウト以外は `.deletionFailed` になることを検証します。
    ///
    /// 責務: 境界未設定の既定の原因を確認します。
    func testOtherErrorsWithoutClassifierResolveToDeletionFailed() {
        XCTAssertEqual(AccountDeletionFailureResolver().failure(for: OtherError()), .deletionFailed)
    }
}
