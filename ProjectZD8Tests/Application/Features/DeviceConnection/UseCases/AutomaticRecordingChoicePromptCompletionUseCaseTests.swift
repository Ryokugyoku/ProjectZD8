import XCTest
@testable import ProjectZD8

/// `AutomaticRecordingChoicePromptCompletionUseCase` が表示済みフラグの読み書きを保存境界へ届けることを検証します。
@MainActor
final class AutomaticRecordingChoicePromptCompletionUseCaseTests: XCTestCase {
    /// 未表示の保存値は未表示として返します。
    ///
    /// 責務: 保存境界が `false` の時に `isCompleted()` が `false` を返すことを確認します。
    func testIsCompletedReturnsFalseWhenPortIsNotCompleted() {
        let useCase = AutomaticRecordingChoicePromptCompletionUseCase(
            completionPort: AutomaticRecordingChoicePromptCompletionFake(isCompleted: false)
        )
        XCTAssertFalse(useCase.isCompleted())
    }

    /// 表示済みの保存値は表示済みとして返します。
    ///
    /// 責務: 保存境界が `true` の時に `isCompleted()` が `true` を返すことを確認します。
    func testIsCompletedReturnsTrueWhenPortIsCompleted() {
        let useCase = AutomaticRecordingChoicePromptCompletionUseCase(
            completionPort: AutomaticRecordingChoicePromptCompletionFake(isCompleted: true)
        )
        XCTAssertTrue(useCase.isCompleted())
    }

    /// 表示済みの記録は保存境界へ1回届き、以後は表示済みとして読めます。
    ///
    /// 責務: `markCompleted()` が保存境界の記録を1回呼び、読み直しが `true` になることを確認します。
    func testMarkCompletedRecordsCompletionThroughPort() {
        let port = AutomaticRecordingChoicePromptCompletionFake(isCompleted: false)
        let useCase = AutomaticRecordingChoicePromptCompletionUseCase(completionPort: port)

        useCase.markCompleted()

        XCTAssertEqual(port.markCount, 1)
        XCTAssertTrue(useCase.isCompleted())
    }
}
