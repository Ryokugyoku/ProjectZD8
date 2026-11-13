#if os(macOS)
import WebKit

/// Webからのスクリプトメッセージを受け取り、ブリッジへ渡します。ページが強参照するため、ブリッジは弱参照で保持します。
final class MacOSAnalysisScriptMessageReceiver: NSObject, WKScriptMessageHandler {
    /// メッセージ名です。Web側の `window.webkit.messageHandlers.analysisBridge` と対応します。
    static let name = "analysisBridge"

    /// 受信したメッセージの処理先です。ページの生成後に設定します。
    var handler: (@MainActor (WKScriptMessage) -> Void)?

    /// 責務: 受信したメッセージを処理先へ渡します。
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { handler?(message) }
    }
}
#endif
