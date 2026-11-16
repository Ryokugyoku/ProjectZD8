import Foundation
@testable import ProjectZD8

/// `RunPostSessionProcessingUseCase` の注入点(クロージャと2つの Port)を差し替えて、呼び出しを記録する部品です。
@MainActor
final class RunPostSessionProcessingUseCaseFixture {
    /// ステップの呼び出し1件です。
    struct StepCall: Equatable {
        /// 呼ばれたステップ。
        let step: PostSessionProcessingStep
        /// 渡されたアカウント識別子。
        let accountIdentifier: String
    }

    /// 診断記録の spy です。
    let diagnostics = PostSessionProcessingDiagnosticsSpy()
    /// 予約の spy です。
    let scheduler = PostSessionProcessingSchedulerSpy()
    /// 記録中かどうかです。ステップの中から書き換えると、以降の判定に反映されます。
    var isRecordingActive = false
    /// 解決されるアカウント識別子です。
    var accountIdentifier: String? = "account-1"
    /// 自動アップロード設定です(どのアカウントにも同じ値を返します)。
    var automaticUploadEnabled = true
    /// アップロードで投げるエラーです。
    var uploadError: (any Error)?
    /// 整理で投げるエラーです。
    var evictionError: (any Error)?
    /// アップロードの中で、エラーを投げる前に行う処理です。
    var duringUpload: (() -> Void)?
    /// 整理の中で、エラーを投げる前に行う処理です。
    var duringEviction: (() -> Void)?
    /// ステップの呼び出し記録です。
    private(set) var stepCalls: [StepCall] = []

    /// 呼ばれたステップの順序です。
    var calledSteps: [PostSessionProcessingStep] {
        stepCalls.map(\.step)
    }

    /// 現在の設定で注入点を結び付けたユースケースを作ります。
    ///
    /// 責務: 本物の `SchedulePostSessionProcessingUseCase` を spy の Port で作り、各クロージャをこの部品の記録へ結び付けます。
    /// - Returns: テスト対象のユースケース。
    func makeUseCase() -> RunPostSessionProcessingUseCase {
        RunPostSessionProcessingUseCase(
            isRecordingActive: { self.isRecordingActive },
            resolveAccountIdentifier: { self.accountIdentifier },
            isAutomaticUploadEnabled: { _ in self.automaticUploadEnabled },
            upload: { accountIdentifier in
                self.stepCalls.append(StepCall(step: .upload, accountIdentifier: accountIdentifier))
                self.duringUpload?()
                if let error = self.uploadError { throw error }
            },
            evictStaleRawLogs: { accountIdentifier in
                self.stepCalls.append(StepCall(step: .eviction, accountIdentifier: accountIdentifier))
                self.duringEviction?()
                if let error = self.evictionError { throw error }
            },
            schedule: SchedulePostSessionProcessingUseCase(scheduler: scheduler, diagnostics: diagnostics),
            diagnostics: diagnostics
        )
    }

    /// ユースケースを `Task` の中で1回実行し、結果を返します。
    ///
    /// 責務: キャンセルを `Task` 単位で起こせるように、実行を独立した `Task` で行います。
    /// - Parameter cancelsBeforeStart: `true` なら実行前にその `Task` 自身をキャンセルします。
    /// 結果は `LiveTelemetryBoundedWaiter` の上限付きで待ち、終わらなければ `XCTFail` して `nil` を返します。
    /// - Returns: 実行結果。上限内に終わらなければ `nil`。
    func run(
        cancelsBeforeStart: Bool = false, file: StaticString = #filePath, line: UInt = #line
    ) async -> PostSessionProcessingOutcome? {
        let useCase = makeUseCase()
        let task = Task { @MainActor in
            if cancelsBeforeStart { Self.cancelCurrentTask() }
            return await useCase.execute()
        }
        return await LiveTelemetryBoundedWaiter.value("後処理の実行", file: file, line: line) { await task.value }
    }

    /// 呼び出し元の `Task` を決定的にキャンセルします(期限切れの代わり)。
    ///
    /// 責務: 時間待ちに頼らず、現在の `Task` のキャンセル状態を立てます。
    static func cancelCurrentTask() {
        withUnsafeCurrentTask { $0?.cancel() }
    }
}
