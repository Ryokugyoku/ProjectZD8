#if os(iOS)
import SwiftUI
import WebKit

/// 指定したセッションを分析する画面です。セッション詳細などから全画面で提示します。
struct IOSAnalysisView: View {
    let model: AnalysisModel
    let sessionID: SessionID
    @State private var host: IOSAnalysisWebHost
    @State private var shareFile: IOSAnalysisShareFile?

    /// 責務: 分析モデル・配信元・開くセッションから、Webホストを作って画面を構成します。
    init(model: AnalysisModel, content: ResolveAnalysisWebContentUseCase, sessionID: SessionID) {
        self.model = model
        self.sessionID = sessionID
        _host = State(initialValue: IOSAnalysisWebHost(content: content, trailingInset: IOSAnalysisMetrics.closeControlInset, send: { model.send($0) }))
    }

    /// 責務: ワークベンチを表示し、セッション選択・ダウンロード確認・共有を提示します。
    var body: some View {
        WebView(host.page)
            .webViewContentBackground(.hidden)
            .task {
                model.send(.appeared)
                model.send(.openSession(sessionID))
            }
            .task(id: model.state) { await host.push(model.state) }
            .onChange(of: model.state.pendingExport) { _, request in
                guard let request else { return }
                shareFile = IOSAnalysisShareFile(request: request)
                if shareFile == nil { model.send(.finishExport) }
            }
            .onDisappear { host.tearDown() }
            .sheet(isPresented: pickerBinding) {
                IOSAnalysisSessionSheet(state: model.state, send: model.send)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $shareFile) { file in
                IOSAnalysisShareSheet(fileURL: file.url) {
                    shareFile = nil
                    model.send(.finishExport)
                }
            }
            .alert(Text("analysis.download.title"), isPresented: downloadPromptBinding) {
                Button("analysis.download.confirm") { model.send(.confirmDownload) }
                Button("analysis.download.cancel", role: .cancel) { model.send(.declineDownload) }
            } message: {
                Text("analysis.download.message")
            }
    }

    /// 責務: セッション選択シートの表示状態を、モデルの要求へ対応づけます。
    private var pickerBinding: Binding<Bool> {
        Binding(
            get: { model.state.pickerPurpose != nil },
            set: { if !$0 { model.send(.dismissSessionPicker) } }
        )
    }

    /// 責務: ダウンロード確認の表示状態を、モデルのフェーズへ対応づけます。
    private var downloadPromptBinding: Binding<Bool> {
        Binding(
            get: { if case .awaitingDownloadConsent = model.state.phase { true } else { false } },
            set: { _ in }
        )
    }
}
#endif
