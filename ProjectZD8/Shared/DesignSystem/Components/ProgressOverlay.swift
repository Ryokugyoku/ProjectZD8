import SwiftUI

/// 処理中を知らせるオーバーレイ。親を覆うスクリムの上に進捗カードを中央表示し、背面の操作をブロックする。
///
/// `progress` が nil なら不確定(スピナー)、値があれば 0...1 の確定進捗。
struct ProgressOverlay: View {
    private let title: Text?
    private let progress: Double?
    private let cancel: InsightAction?

    /// オーバーレイを作る。
    ///
    /// 責務: 文言・進捗・任意のキャンセル操作を保持する。
    init(title: Text? = nil, progress: Double? = nil, cancel: InsightAction? = nil) {
        self.title = title
        self.progress = progress
        self.cancel = cancel
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)
            VStack(spacing: InsightSpacing.md) {
                if let progress {
                    ProgressView(value: min(1, max(0, progress)))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 220)
                } else {
                    ProgressView()
                }
                if let title {
                    title.font(InsightTypography.caption).multilineTextAlignment(.center)
                }
                if let cancel {
                    Button(action: cancel.handler) { cancel.title }
                        .buttonStyle(.insightSecondary)
                }
            }
            .padding(InsightSpacing.xl)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: InsightRadius.lg, style: .continuous)
                    .fill(.regularMaterial)
            )
            .accessibilityElement(children: .contain)
        }
    }
}

extension View {
    /// 条件付きで進捗オーバーレイを重ねる。
    ///
    /// 責務: isPresented が true の間だけ ProgressOverlay を全面に重ねる。
    func insightProgressOverlay(
        isPresented: Bool,
        title: Text? = nil,
        progress: Double? = nil,
        cancel: InsightAction? = nil
    ) -> some View {
        overlay {
            if isPresented { ProgressOverlay(title: title, progress: progress, cancel: cancel) }
        }
    }
}

#Preview("Light") {
    Text(verbatim: "Content")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InsightBackground())
        .insightProgressOverlay(isPresented: true, title: Text(verbatim: "Importing…"), progress: 0.4,
                                cancel: InsightAction(Text(verbatim: "Cancel")) {})
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    Text(verbatim: "Content")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InsightBackground())
        .insightProgressOverlay(isPresented: true, title: Text(verbatim: "Connecting…"))
        .preferredColorScheme(.dark)
}
