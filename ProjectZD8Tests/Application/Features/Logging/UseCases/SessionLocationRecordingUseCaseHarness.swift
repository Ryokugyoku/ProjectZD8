import Foundation
import XCTest
@testable import ProjectZD8

/// `SessionLocationRecordingUseCase` のテストが共有する組み立てと、期限つきの確認をまとめた土台です。
@MainActor
final class SessionLocationRecordingUseCaseHarness {
    /// 事象の時刻として注入する固定の時刻です。
    static let fixedNow = Date(timeIntervalSince1970: 1_900_000_000)

    /// 位置の購読口の fake です。
    let subscription: LocationUpdateSubscriptionFake
    /// 位置の Repository の spy です。
    let repository: ConnectionSessionLocationRepositorySpy
    /// 診断の spy です。
    let diagnostics: SessionLocationRecordingDiagnosticsSpy
    /// テスト対象のユースケースです。
    let useCase: SessionLocationRecordingUseCase

    /// 初期条件を指定して組み立てます。
    ///
    /// 責務: fake と spy につながり、固定の時刻を返すユースケースを生成します。
    /// - Parameters:
    ///   - isRecordingEnabled: 走行ルート記録設定の初期値。
    ///   - permission: 許可状態の初期値。
    ///   - isForeground: 前面にいるかどうかの初期値。
    init(isRecordingEnabled: Bool, permission: LocationPermission, isForeground: Bool) {
        let subscription = LocationUpdateSubscriptionFake()
        let repository = ConnectionSessionLocationRepositorySpy()
        let diagnostics = SessionLocationRecordingDiagnosticsSpy()
        self.subscription = subscription
        self.repository = repository
        self.diagnostics = diagnostics
        let fixedNow = Self.fixedNow
        useCase = SessionLocationRecordingUseCase(
            locations: subscription,
            recorder: ConnectionSessionLocationRecorder(repository: repository, diagnostics: diagnostics),
            repository: repository,
            diagnostics: diagnostics,
            isRecordingEnabled: isRecordingEnabled,
            permission: permission,
            isForeground: isForeground,
            now: { fixedNow }
        )
    }

    /// 許可状態を作ります。
    ///
    /// 責務: 許可の段階と精度から許可状態を返します。
    /// - Parameters:
    ///   - level: 許可の段階。
    ///   - isPreciseAccuracy: 正確な位置が許可されている場合は `true`。
    /// - Returns: 許可状態。
    static func permission(_ level: LocationAuthorizationLevel, isPreciseAccuracy: Bool = true) -> LocationPermission {
        LocationPermission(level: level, isPreciseAccuracy: isPreciseAccuracy)
    }

    /// セッションの事象の種類が期待どおりになるまで待ちます。
    ///
    /// 責務: 期限つきで事象の種類の並びを確かめ、満たさなければテストを失敗させます。
    /// - Parameters:
    ///   - expected: 期待する事象の種類(追記順)。
    ///   - sessionID: 対象の接続セッション。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    func waitForEventKinds(
        _ expected: [ConnectionSessionLocationEventKind],
        for sessionID: ConnectionSessionID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await LocationRecordingBoundedWaiter.waitUntil("事象が \(expected) になる", file: file, line: line) {
            repository.storedEventKinds(for: sessionID) == expected
        }
    }

    /// 購読回数と終了回数が期待どおりになるまで待ちます。
    ///
    /// 責務: 期限つきで購読の開始と取消の回数を確かめ、満たさなければテストを失敗させます。
    /// - Parameters:
    ///   - subscribed: 期待する購読回数。
    ///   - terminated: 期待する購読の終了回数。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    func waitForSubscriptions(subscribed: Int, terminated: Int, file: StaticString = #filePath, line: UInt = #line) async {
        await LocationRecordingBoundedWaiter.waitUntil(
            "購読 \(subscribed) 回・終了 \(terminated) 回になる", file: file, line: line
        ) {
            subscription.subscribeCallCount == subscribed && subscription.terminationCount == terminated
        }
    }

    /// 最新の購読へ位置を流し、そのセッションへ保存されるまで待ちます。
    ///
    /// 責務: 位置を1点流し、保存済みの位置の末尾がその点になることを期限つきで確かめます。
    /// - Parameters:
    ///   - index: 位置を区別する番号。
    ///   - sessionID: 保存先として期待する接続セッション。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: 流した位置。
    /// - Throws: 位置を作れない場合のテスト失敗。
    @discardableResult
    func yieldFixAndWaitSaved(
        index: Int,
        to sessionID: ConnectionSessionID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> LocationFix {
        let fix = try ConnectionSessionLocationTestValues.fix(index: index)
        subscription.yield(.fix(fix))
        await LocationRecordingBoundedWaiter.waitUntil("位置が保存される", file: file, line: line) {
            repository.storedFixes(for: sessionID).last == fix
        }
        return fix
    }

    /// 否定の確認の前に、起きてはいけない処理が走り得る時間だけ待ちます。
    ///
    /// 責務: 固定回数だけ他のタスクへ実行機会を渡します。
    func settle() async {
        await LocationRecordingBoundedWaiter.settle()
    }

    /// 後始末をします。
    ///
    /// 責務: セッションを外して購読を取消させ、残った流れを終えて記録のタスクを止めます。
    func tearDown() {
        useCase.activeSessionDidChange(nil)
        subscription.finishAll()
    }
}
