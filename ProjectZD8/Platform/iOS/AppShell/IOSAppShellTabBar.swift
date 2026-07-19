#if os(iOS)
import SwiftUI

/// iPhoneの親指操作に合わせたAppShell下部ナビゲーションを描画します。
struct IOSAppShellTabBar: View {
    /// 選択中の遷移先をiOS AppShellと共有します。
    @Binding var selection: IOSAppShellDestination

    /// ユーザーが動きを減らす設定を有効にしているかを示します。
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// 現在のDynamic Type設定です。
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 4件の遷移先を半透明のフローティングドックとして提供します。
    ///
    /// 責務: iOS用の下部ナビゲーションを描画し、選択操作をバインディングへ反映します。
    var body: some View {
        HStack(spacing: 4) {
            ForEach(IOSAppShellDestination.allCases) { destination in
                destinationButton(for: destination)
            }
        }
        .padding(7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 20, y: 8)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-tab-bar")
    }

    /// 1件の遷移先を選択可能なタブとして生成します。
    ///
    /// 責務: 1件の遷移先を描画し、操作時にその選択だけを反映します。
    /// - Parameter destination: ボタンが表すプレゼンテーション専用の遷移先。
    /// - Returns: 現在の選択状態を複数の視覚手掛かりで示すボタン。
    private func destinationButton(for destination: IOSAppShellDestination) -> some View {
        let isSelected = selection == destination

        return Button {
            selection = destination
        } label: {
            VStack(spacing: 4) {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolEffect(.bounce, value: isSelected)

                if !dynamicTypeSize.isAccessibilitySize {
                    Text(destination.compactTitle)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.62))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.9) : Color.clear)
                    .frame(width: 16, height: 2)
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(accessibilityReduceMotion ? nil : .snappy(duration: 0.2), value: isSelected)
        .accessibilityLabel(Text(destination.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("ios-tab-\(destination.rawValue)")
    }
}
#endif
