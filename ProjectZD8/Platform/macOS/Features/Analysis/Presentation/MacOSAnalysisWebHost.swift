#if os(macOS)
import Foundation
import OSLog
import WebKit

/// ワークベンチを表示するWebページと、ネイティブとのメッセージ往復を所有します。
@MainActor
final class MacOSAnalysisWebHost {
    /// 表示するページです。
    let page: WebPage

    private static let logger = Logger(subsystem: "ProjectZD8", category: "AnalysisWeb")
    private let send: (AnalysisAction) -> Void
    private var receiver: MacOSAnalysisScriptMessageReceiver?
    private let userContentController: WKUserContentController
    /// ワークベンチが `ready` を通知済みで、設定メッセージを受け取れるかどうかです。
    private(set) var isWebReady = false
    private var lastPushed: AnalysisHostMessage?
    /// ワークベンチの準備が整う前に届いた最新の状態です。準備完了の通知を受けた時点で送ります。
    private var latestState: AnalysisState?

    /// 責務: スキームハンドラ・メッセージ経路・遷移制限を備えたページを組み立て、入口を読み込みます。
    init(content: ResolveAnalysisWebContentUseCase, send: @escaping (AnalysisAction) -> Void) {
        self.send = send
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.upgradeKnownHostsToHTTPS = false
        if let scheme = URLScheme(ResolveAnalysisWebContentUseCase.scheme) {
            configuration.urlSchemeHandlers[scheme] = MacOSAnalysisSchemeHandler(content: content)
        }
        let receiver = MacOSAnalysisScriptMessageReceiver()
        self.receiver = receiver
        userContentController = configuration.userContentController
        userContentController.add(receiver, name: MacOSAnalysisScriptMessageReceiver.name)
        page = WebPage(configuration: configuration, navigationDecider: MacOSAnalysisNavigationDecider())
        receiver.handler = { [weak self] message in self?.receive(message) }
        page.load(URLRequest(url: ResolveAnalysisWebContentUseCase.indexURL))
    }

    /// 責務: 受信メッセージを検証して処理します。ワークベンチ以外のページからのものは無視します。
    private func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == ResolveAnalysisWebContentUseCase.scheme else {
            Self.logger.error("Ignored a message from an unexpected frame")
            return
        }
        do {
            let decoded = try AnalysisWebMessage.decode(message.body)
            if decoded == .ready {
                isWebReady = true
                lastPushed = nil
                if let state = latestState {
                    Task { await push(state) }
                }
            } else if let action = decoded.action {
                send(action)
            }
        } catch {
            Self.logger.error("Ignored an invalid message: \(String(describing: error), privacy: .public)")
        }
    }

    /// 現在の状態をワークベンチへ送ります。ページの準備前、または前回と同じ内容なら何もしません。
    ///
    /// 責務: 画面状態の変化をWeb側の設定メッセージへ写して送ります。
    func push(_ state: AnalysisState) async {
        latestState = state
        guard isWebReady else { return }
        let message = AnalysisHostMessage(state: state)
        guard message != lastPushed else { return }
        lastPushed = message
        do {
            let json = try message.jsonString()
            _ = try await page.callJavaScript("window.RTHost && window.RTHost.receive(JSON.parse(message))", arguments: ["message": json])
        } catch {
            lastPushed = nil
            Self.logger.error("Pushing state to the web view failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// 責務: メッセージ経路を解除し、読み込みを止めます。
    func tearDown() {
        userContentController.removeScriptMessageHandler(forName: MacOSAnalysisScriptMessageReceiver.name)
        page.stopLoading()
        receiver = nil
    }
}
#endif
