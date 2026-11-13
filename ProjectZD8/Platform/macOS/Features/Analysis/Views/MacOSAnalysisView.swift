#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// 車両別のセッション一覧と、分析ワークベンチ(Webビュー)を並べた分析画面です。
struct MacOSAnalysisView: View {
    let model: AnalysisModel
    @State private var host: MacOSAnalysisWebHost

    /// 責務: 分析モデルと配信元から、Webホストを作って画面を構成します。
    init(model: AnalysisModel, content: ResolveAnalysisWebContentUseCase) {
        self.model = model
        _host = State(initialValue: MacOSAnalysisWebHost(content: content, send: { model.send($0) }))
    }

    /// 責務: 一覧とワークベンチを並べ、ダウンロード確認と書き出しを提示します。
    var body: some View {
        HSplitView {
            MacOSAnalysisSessionList(state: model.state, send: model.send)
                .frame(minWidth: MacOSAnalysisMetrics.listMinWidth, idealWidth: MacOSAnalysisMetrics.listIdealWidth, maxWidth: MacOSAnalysisMetrics.listMaxWidth)
            WebView(host.page)
                .webViewContentBackground(.hidden)
                .frame(minWidth: MacOSAnalysisMetrics.webMinWidth)
        }
        .task { model.send(.appeared) }
        .task(id: model.state) { await host.push(model.state) }
        .onDisappear { host.tearDown() }
        .alert(Text("analysis.download.title"), isPresented: downloadPromptBinding) {
            Button("analysis.download.confirm") { model.send(.confirmDownload) }
            Button("analysis.download.cancel", role: .cancel) { model.send(.declineDownload) }
        } message: {
            Text("analysis.download.message")
        }
        .fileExporter(
            isPresented: exportBinding,
            document: MacOSAnalysisExportDocument(data: model.state.pendingExport?.data ?? Data()),
            contentType: exportType,
            defaultFilename: model.state.pendingExport?.filename ?? "export"
        ) { _ in model.send(.finishExport) }
    }

    /// 責務: ダウンロード確認の表示状態を、モデルのフェーズへ対応づけます。
    private var downloadPromptBinding: Binding<Bool> {
        Binding(
            get: { if case .awaitingDownloadConsent = model.state.phase { true } else { false } },
            set: { _ in }
        )
    }

    /// 責務: 書き出しシートの表示状態を、保留中の書き出しへ対応づけます。
    private var exportBinding: Binding<Bool> {
        Binding(
            get: { model.state.pendingExport != nil },
            set: { if !$0 { model.send(.finishExport) } }
        )
    }

    /// 責務: 保留中の書き出しのMIMEタイプを、保存パネルの種別へ変換します。
    private var exportType: UTType {
        model.state.pendingExport?.mimeType == "image/png" ? .png : .commaSeparatedText
    }
}
#endif
