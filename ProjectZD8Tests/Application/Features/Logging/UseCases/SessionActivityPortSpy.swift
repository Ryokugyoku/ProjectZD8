@testable import ProjectZD8

/// 常時表示の境界の偽物です。呼び出しを記録し、指定した失敗を返します。
@MainActor
final class SessionActivityPortSpy: SessionActivityPort {
    /// 表示が出ているかどうかです。開始成功で真、終了成功で偽になります。
    var isPresenting = false
    /// 開始が受け取った内容です。
    private(set) var startedContents: [RecordingSessionActivityContent] = []
    /// 更新が受け取った内容です。
    private(set) var updatedContents: [RecordingSessionActivityContent] = []
    /// 終了が受け取った最終内容です。
    private(set) var endedContents: [RecordingSessionActivityContent] = []
    /// 設定すると開始がこのエラーを投げます。
    var startError: (any Error)?
    /// 設定すると更新がこのエラーを投げます。
    var updateError: (any Error)?
    /// 設定すると終了がこのエラーを投げます。
    var endError: (any Error)?

    /// 開始を記録します。
    ///
    /// 責務: 内容を記録し、エラー指定が無ければ表示中にします。
    func start(_ content: RecordingSessionActivityContent) async throws {
        startedContents.append(content)
        if let startError { throw startError }
        isPresenting = true
    }

    /// 更新を記録します。
    ///
    /// 責務: 内容を記録し、エラー指定があれば投げます。
    func update(_ content: RecordingSessionActivityContent) async throws {
        updatedContents.append(content)
        if let updateError { throw updateError }
    }

    /// 終了を記録します。
    ///
    /// 責務: 最終内容を記録し、エラー指定が無ければ表示を閉じます。
    func end(_ finalContent: RecordingSessionActivityContent) async throws {
        endedContents.append(finalContent)
        if let endError { throw endError }
        isPresenting = false
    }

    /// システムが表示を終了した状況(8時間上限等)を再現します。
    ///
    /// 責務: 呼び出しを伴わず表示中でなくします。
    func simulateSystemDismissal() {
        isPresenting = false
    }
}
