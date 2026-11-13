#if os(macOS)
import SwiftUI

/// サイドバー下部の iCloud 同期状態。「同期済み」は状態の裏付けがある時だけ表示する。
struct MacOSSyncStatusFooter: View {
    let state: SyncState

    var body: some View {
        HStack(alignment: .top, spacing: InsightSpacing.sm) {
            if state.status == .syncing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(tone.color)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
                Text("sync.footer.title").font(InsightTypography.label)
                Text(LocalizedStringKey(state.statusMessageKey))
                    .font(InsightTypography.footnote)
                    .foregroundStyle(.secondary)
                if case .idle(let last?) = state.status {
                    Text(last, format: .relative(presentation: .named))
                        .font(InsightTypography.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch state.status {
        case .unavailable: "icloud.slash"
        case .idle(let last): last == nil ? "icloud" : "checkmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .failed: "exclamationmark.icloud"
        }
    }

    private var tone: StatusTone {
        switch state.status {
        case .unavailable: .neutral
        case .idle(let last): last == nil ? .neutral : .positive
        case .syncing: .active
        case .failed: .critical
        }
    }
}
#endif
