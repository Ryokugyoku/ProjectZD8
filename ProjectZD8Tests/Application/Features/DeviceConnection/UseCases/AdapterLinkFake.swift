import Foundation
@testable import ProjectZD8

/// 常駐リンクの fake です。開始・停止の呼び出しを記録し、状態の変化をテストから流します。
///
/// 本番の `BLEAdapterLink` と同じく、`stop()` は状態が変わる場合に `idle` への変化を同期で通知します。
@MainActor
final class AdapterLinkFake: AdapterLinkPort {
    /// 現在のリンク状態です。
    private(set) var state: AdapterLinkState = .idle

    /// リンク状態が変化したときに新しい状態を受け取る処理です。
    var stateDidChange: (@MainActor (AdapterLinkState) -> Void)?

    /// 受信したバイトを受け取る処理です(監視では使いません)。
    var dataDidReceive: (@MainActor (Data) -> Void)?

    /// `start(preference:)` に渡された設定です(呼び出し順)。
    private(set) var startedPreferences: [DefaultAdapterPreference] = []

    /// `stop()` が呼ばれた回数です。
    private(set) var stopCount = 0

    /// 開始・停止の呼び出し順の記録です。
    private(set) var calls: [String] = []

    /// リンクの開始を記録します。状態はテストが `emit(_:)` で進めます。
    ///
    /// 責務: 開始の引数と順序を記録します。
    /// - Parameter preference: 接続対象の設定。
    func start(preference: DefaultAdapterPreference) {
        startedPreferences.append(preference)
        calls.append("start:\(preference.adapterID)")
    }

    /// リンクの停止を記録し、`idle` へ戻します。
    ///
    /// 責務: 停止回数と順序を記録し、状態が変わる場合は `idle` への変化を通知します。
    func stop() {
        stopCount += 1
        calls.append("stop")
        guard state != .idle else { return }
        emit(.idle)
    }

    /// 書き込みは監視では使わないため、常に `notReady` で失敗します。
    ///
    /// 責務: 監視が書き込みへ依存していないことを前提に、呼ばれても成功を装いません。
    /// - Parameter data: 送信するバイト列。
    func write(_ data: Data) async throws {
        throw AdapterLinkWriteError.notReady
    }

    /// リンク状態を変えて通知します。同じ状態でも通知します(再通知の検証用)。
    ///
    /// 責務: テストが指定したリンク状態を現在値にし、受け口へ渡します。
    /// - Parameter newState: 新しいリンク状態。
    func emit(_ newState: AdapterLinkState) {
        state = newState
        stateDidChange?(newState)
    }
}
