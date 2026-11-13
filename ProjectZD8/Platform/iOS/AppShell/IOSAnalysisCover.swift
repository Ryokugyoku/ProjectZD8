#if os(iOS)
import SwiftUI

/// 分析画面を全画面で包み、閉じる操作を重ねます。
struct IOSAnalysisCover<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: IOSAppShellMetrics.closeButtonSide, height: IOSAppShellMetrics.closeButtonSide)
                    .insightFloatingGlass(cornerRadius: IOSAppShellMetrics.closeButtonSide / 2)
            }
            .buttonStyle(.plain)
            .padding(InsightSpacing.md)
            .accessibilityLabel(Text("shell.analysis.close"))
        }
    }
}
#endif
