#if os(macOS)
import SwiftUI

/// macOSでApple認証前の免責事項と明示同意操作を表示します。
struct MacOSLoginDisclaimerView: View {
    /// 免責事項を閉じる操作です。
    let dismiss: () -> Void

    /// 免責事項への同意後にApple認証を開始する操作です。
    let accept: () -> Void

    /// Macウインドウ内で読み切れる免責事項と同意操作を描画します。
    ///
    /// 責務: macOS向け免責事項を明示同意が必要なシートとして表示します。
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 46, height: 46)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("auth.disclaimer.title")
                        .font(.title2.weight(.bold))
                    Text("auth.disclaimer.instruction")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("auth.disclaimer.introduction")
                        .font(.headline)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 230), spacing: 14)],
                        spacing: 14
                    ) {
                        disclaimerCard(
                            symbol: "steeringwheel",
                            titleKey: "auth.disclaimer.risk.title",
                            bodyKey: "auth.disclaimer.risk.body"
                        )
                        disclaimerCard(
                            symbol: "wrench.and.screwdriver",
                            titleKey: "auth.disclaimer.no_warranty.title",
                            bodyKey: "auth.disclaimer.no_warranty.body"
                        )
                        disclaimerCard(
                            symbol: "exclamationmark.shield",
                            titleKey: "auth.disclaimer.liability.title",
                            bodyKey: "auth.disclaimer.liability.body"
                        )
                        disclaimerCard(
                            symbol: "hand.raised.fill",
                            titleKey: "auth.disclaimer.safety.title",
                            bodyKey: "auth.disclaimer.safety.body"
                        )
                    }
                    Text("auth.disclaimer.legal_note")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }

            Divider()

            HStack(spacing: 12) {
                Button("auth.disclaimer.cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: accept) {
                    Label("auth.disclaimer.accept", systemImage: "apple.logo")
                        .frame(minWidth: 210)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("macos-auth-disclaimer-accept")
            }
            .padding(20)
        }
        .frame(minWidth: 520, idealWidth: 680, minHeight: 420, idealHeight: 620)
        .interactiveDismissDisabled()
        .accessibilityIdentifier("macos-auth-disclaimer")
    }

    /// 免責事項の1項目を読みやすいカードとして描画します。
    ///
    /// 責務: 1件の免責事項をmacOS用の独立した情報カードへ変換します。
    /// - Parameters:
    ///   - symbol: 項目の意味を補助するSF Symbol名。
    ///   - titleKey: ローカライズ済み見出しのキー。
    ///   - bodyKey: ローカライズ済み本文のキー。
    /// - Returns: 免責事項1件のmacOS表示。
    private func disclaimerCard(
        symbol: String,
        titleKey: LocalizedStringKey,
        bodyKey: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(titleKey)
                    .font(.headline)
                Text(bodyKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
#endif
