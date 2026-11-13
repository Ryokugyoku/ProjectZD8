#if os(iOS)
import SwiftUI

/// iOSでApple認証前の免責事項と明示同意操作を表示します。
struct IOSLoginDisclaimerView: View {
    /// 免責事項を閉じる操作です。
    let dismiss: () -> Void

    /// 免責事項への同意後にApple認証を開始する操作です。
    let accept: () -> Void

    /// iPhoneで読み切れる免責事項と同意操作を描画します。
    ///
    /// 責務: iOS向け免責事項を明示同意が必要なモーダルとして表示します。
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    disclaimerHeader
                    disclaimerSection(
                        symbol: "steeringwheel",
                        titleKey: "auth.disclaimer.risk.title",
                        bodyKey: "auth.disclaimer.risk.body"
                    )
                    disclaimerSection(
                        symbol: "wrench.and.screwdriver",
                        titleKey: "auth.disclaimer.no_warranty.title",
                        bodyKey: "auth.disclaimer.no_warranty.body"
                    )
                    disclaimerSection(
                        symbol: "exclamationmark.shield",
                        titleKey: "auth.disclaimer.liability.title",
                        bodyKey: "auth.disclaimer.liability.body"
                    )
                    disclaimerSection(
                        symbol: "hand.raised.fill",
                        titleKey: "auth.disclaimer.safety.title",
                        bodyKey: "auth.disclaimer.safety.body"
                    )
                    Text("auth.disclaimer.legal_note")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    acceptButton
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .navigationTitle(Text("auth.disclaimer.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("auth.disclaimer.cancel", action: dismiss)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
        .accessibilityIdentifier("ios-auth-disclaimer")
    }

    /// 免責事項の目的を示すヘッダーです。
    private var disclaimerHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)
            Text("auth.disclaimer.introduction")
                .font(.title3.weight(.semibold))
            Text("auth.disclaimer.instruction")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    /// 免責事項への同意とApple認証開始を通知するボタンです。
    private var acceptButton: some View {
        Button(action: accept) {
            Label("auth.disclaimer.accept", systemImage: "apple.logo")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .accessibilityIdentifier("ios-auth-disclaimer-accept")
    }

    /// 免責事項の1項目をアイコン、見出し、本文で描画します。
    ///
    /// 責務: 1件の免責事項をiOS用の読みやすい情報行へ変換します。
    /// - Parameters:
    ///   - symbol: 項目の意味を補助するSF Symbol名。
    ///   - titleKey: ローカライズ済み見出しのキー。
    ///   - bodyKey: ローカライズ済み本文のキー。
    /// - Returns: 免責事項1件のiOS表示。
    private func disclaimerSection(
        symbol: String,
        titleKey: LocalizedStringKey,
        bodyKey: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
    }
}
#endif
