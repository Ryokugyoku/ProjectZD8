#if os(iOS)
/// [切断]の LiveActivityIntent が呼ぶ停止処理の登録先です。アプリとWidget Extensionの両方に属します。
///
/// アプリのプロセスでは起動時の配線が停止処理を登録します。Extensionのプロセスでは何も登録されないため、
/// `performStop()` は何もしません(LiveActivityIntent はアプリのプロセスで実行されます)。
@MainActor
enum RecordingSessionStopIntentHandlerRegistry {
    /// 登録済みの停止処理です。登録前・Extensionでは `nil` です。
    private static var stopHandler: (@MainActor () -> Void)?

    /// 停止処理を登録します。後から登録した処理で置き換えます。
    ///
    /// 責務: [切断]操作の実行先をアプリの停止処理へ結び付けます。
    /// - Parameter handler: 記録中なら停止を要求し、記録中でなければ何もしない処理。
    static func register(_ handler: @escaping @MainActor () -> Void) {
        stopHandler = handler
    }

    /// 登録済みの停止処理を実行します。
    ///
    /// 責務: [切断]操作を登録済みの停止処理へ渡します。未登録なら何もしません。
    static func performStop() {
        stopHandler?()
    }
}
#endif
