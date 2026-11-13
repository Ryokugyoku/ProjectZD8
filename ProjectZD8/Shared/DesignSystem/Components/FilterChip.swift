import SwiftUI

/// 絞り込み用のトグルチップ。選択状態は色と VoiceOver の選択トレイトで伝える。
struct FilterChip: View {
    @Environment(\.colorSchemeContrast) private var contrast

    private let title: Text
    private let isSelected: Bool
    private let action: () -> Void

    /// チップを作る。
    ///
    /// 責務: タイトル・選択状態・タップ処理を保持する。
    init(_ title: Text, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            title
                .font(InsightTypography.label)
                .lineLimit(1)
                .foregroundStyle(isSelected ? InsightPalette.accent : Color.primary)
                .padding(.horizontal, InsightSpacing.md)
                .frame(minHeight: InsightSpacing.minimumHitTarget - 8)
                .background(Capsule().fill(isSelected ? InsightPalette.accent.opacity(0.16) : InsightPalette.surface))
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? InsightPalette.accent.opacity(0.6) : InsightPalette.border(for: contrast),
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Light") {
    HStack {
        FilterChip(Text(verbatim: "All"), isSelected: true) {}
        FilterChip(Text(verbatim: "Today"), isSelected: false) {}
        FilterChip(Text(verbatim: "Warnings"), isSelected: false) {}
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    HStack {
        FilterChip(Text(verbatim: "All"), isSelected: true) {}
        FilterChip(Text(verbatim: "Today"), isSelected: false) {}
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.dark)
}
