import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの読み込みの失敗の分類を検証します。
@MainActor
final class DrivingRouteFailureClassifierTests: XCTestCase {
    /// 検証対象です。
    private let classifier = DrivingRouteFailureClassifier()

    /// 分類に使う、どの種類にも当たらない独自のエラーです。
    private struct UnrelatedError: Error {}

    /// 新しい形式の軌跡は「アプリの更新が必要」で、再試行できません。
    ///
    /// 責務: `unsupportedPayloadFormat` が版の値によらず更新のキーと再試行不可になることを確認します。
    func testUnsupportedPayloadFormatRequiresUpdateWithoutRetry() {
        for version in [Int64(2), Int64(99)] {
            let failure = classifier.failure(for: ConnectionSessionLocationTrackCloudError.unsupportedPayloadFormat(version: version))

            XCTAssertEqual(failure, DrivingRouteFailure(messageKey: "history.route.failure.update_required", isRetryable: false))
        }
    }

    /// それ以外のエラーは「読み込めませんでした」で、再試行できます。
    ///
    /// 責務: 通信・リポジトリ・独自のエラーがすべて読み込み失敗のキーと再試行可になることを確認します。
    func testOtherErrorsAreRetryableLoadFailures() {
        let errors: [any Error] = [
            URLError(.notConnectedToInternet),
            ConnectionSessionRepositoryError.invalidState,
            UnrelatedError(),
        ]

        for error in errors {
            XCTAssertEqual(
                classifier.failure(for: error),
                DrivingRouteFailure(messageKey: "history.route.failure.load", isRetryable: true),
                "\(error)"
            )
        }
    }
}
