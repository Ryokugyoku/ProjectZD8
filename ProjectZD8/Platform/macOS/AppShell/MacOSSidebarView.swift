#if os(macOS)
import SwiftUI

/// macOS AppShell専用のフローティングナビゲーションを描画します。
struct MacOSSidebarView: View {
    /// 選択中の遷移先をmacOS AppShellと共有します。
    @Binding var selection: MacOSSidebarDestination

    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// ポインターが重なっている遷移先を一時的に保持します。
    @State private var hoveredDestination: MacOSSidebarDestination?

    /// ユーザーが動きを減らす設定を有効にしているかを示します。
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// ブランド表示とナビゲーション行を持つサイドバーを提供します。
    ///
    /// 責務: macOS用サイドバーを描画し、選択操作をバインディングへ反映します。
    var body: some View {
        ZStack {
            sidebarBackground

            VStack(alignment: .leading, spacing: 0) {
                brandHeader

                Text("sidebar.section.navigation")
                    .font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded))
                    .tracking(1.8 * metrics.scale)
                    .foregroundStyle(.secondary)
                    .padding(.top, (metrics.usesCompactSidebarHeight ? 10 : 26) * metrics.scale)
                    .padding(.horizontal, 10 * metrics.scale)

                VStack(spacing: metrics.rowSpacing) {
                    ForEach(MacOSSidebarDestination.allCases) { destination in
                        destinationButton(for: destination)
                    }
                }
                .padding(.top, 10 * metrics.scale)

                Spacer(minLength: 20 * metrics.scale)

                if !metrics.usesCompactSidebarHeight {
                    footer
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
        }
        .frame(width: metrics.sidebarWidth)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-sidebar")
    }

    /// サイドバーの半透明な背景レイヤーです。
    private var sidebarBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.clear,
                    Color.black.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(Color.white.opacity(0.025))
        }
        .ignoresSafeArea()
    }

    /// 製品名とアプリアイコンをまとめたブランド表示です。
    private var brandHeader: some View {
        HStack(spacing: 12 * metrics.scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 13 * metrics.scale, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.accentColor.opacity(0.32), radius: 12 * metrics.scale, y: 5 * metrics.scale)

                Image(systemName: "car.side.fill")
                    .font(.system(size: 20 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44 * metrics.scale, height: 44 * metrics.scale)

            VStack(alignment: .leading, spacing: 1 * metrics.scale) {
                Text("Project ZD8")
                    .font(.system(size: 17 * metrics.scale, weight: .bold, design: .rounded))

                Text("sidebar.brand.tagline")
                    .font(.system(size: 9 * metrics.scale, weight: .semibold, design: .rounded))
                    .tracking(1.1 * metrics.scale)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8 * metrics.scale)
    }

    /// サイドバー下端にアプリの表示コンテキストを示す装飾カードです。
    private var footer: some View {
        HStack(spacing: 10 * metrics.scale) {
            Image(systemName: "sparkles")
                .font(.system(size: 13 * metrics.scale, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28 * metrics.scale, height: 28 * metrics.scale)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            Text("sidebar.footer.caption")
                .font(.system(size: 11 * metrics.scale, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(10 * metrics.scale)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14 * metrics.scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14 * metrics.scale, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    /// 1件の遷移先を選択可能なナビゲーション行として生成します。
    ///
    /// 責務: 1件の遷移先を描画し、操作時にその選択だけを反映します。
    /// - Parameter destination: 行が表すプレゼンテーション専用の遷移先。
    /// - Returns: 選択状態とホバー状態を反映したボタン。
    private func destinationButton(for destination: MacOSSidebarDestination) -> some View {
        let isSelected = selection == destination
        let isHovered = hoveredDestination == destination

        return Button {
            selection = destination
        } label: {
            HStack(spacing: 12 * metrics.scale) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10 * metrics.scale, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.09 : 0.055))

                    Image(systemName: destination.systemImage)
                        .font(.system(size: metrics.symbolSize, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.82))
                }
                .frame(width: 38 * metrics.scale, height: 38 * metrics.scale)
                .shadow(
                    color: isSelected ? Color.accentColor.opacity(0.30) : Color.clear,
                    radius: 8 * metrics.scale,
                    y: 3 * metrics.scale
                )

                VStack(alignment: .leading, spacing: 2 * metrics.scale) {
                    Text(destination.title)
                        .font(.system(size: 14 * metrics.scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if !metrics.usesCompactSidebarHeight {
                        Text(destination.subtitle)
                            .font(.system(size: 10.5 * metrics.scale, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4 * metrics.scale)

                Text(destination.shortcutLabel)
                    .font(.system(size: 10 * metrics.scale, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered || isSelected ? 1 : 0)
            }
            .padding(.horizontal, 9 * metrics.scale)
            .frame(maxWidth: .infinity, minHeight: metrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 15 * metrics.scale, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(isHovered ? 0.045 : 0))
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3 * metrics.scale, height: isSelected ? 24 * metrics.scale : 0)
                .offset(x: -1 * metrics.scale)
                .shadow(color: Color.accentColor.opacity(0.55), radius: 5 * metrics.scale)
        }
        .scaleEffect(isHovered && !isSelected && !accessibilityReduceMotion ? 1.012 : 1)
        .animation(accessibilityReduceMotion ? nil : .snappy(duration: 0.18), value: isSelected)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .onHover { isInside in
            hoveredDestination = isInside ? destination : nil
        }
        .keyboardShortcut(destination.shortcut, modifiers: .command)
        .accessibilityLabel(Text(destination.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("macos-sidebar-\(destination.rawValue)")
    }
}
#endif
