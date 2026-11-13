import Foundation
import Synchronization
@testable import ProjectZD8

/// メモリ上のテスト用 `AppSettingsStorePort` です。
final class RecordsFakeSettingsStore: AppSettingsStorePort, Sendable {
    private let state: Mutex<State>

    private struct State {
        var settings: AppSettings
        var saveCount = 0
    }

    init(settings: AppSettings = AppSettings(localRawRetention: .days30)) {
        state = Mutex(State(settings: settings))
    }

    var current: AppSettings { state.withLock { $0.settings } }
    var saveCount: Int { state.withLock { $0.saveCount } }
    /// 保存を経由せずに保存内容を差し替えます(他端末や他プロセスの変更を模擬します)。
    func overwrite(_ settings: AppSettings) { state.withLock { $0.settings = settings } }

    func load() -> AppSettings { state.withLock { $0.settings } }

    func save(_ settings: AppSettings) {
        state.withLock {
            $0.settings = settings
            $0.saveCount += 1
        }
    }
}
