#if os(iOS)
import SwiftUI

/// 選択されたiOS遷移先に対応する画面を描画します。
struct IOSDestinationView: View {
    /// この画面が表す遷移先です。
    let destination: IOSAppShellDestination

    /// 設定画面へ渡す現在の表示設定です。
    let settingsState: IOSSettingsState

    /// HOMEの操作をAppShellへ通知するクロージャです。
    let sendHomeAction: (IOSHomeAction) -> Void

    /// 設定画面の操作をAppShellへ通知するクロージャです。
    let sendSettingsAction: (IOSSettingsAction) -> Void

    /// 選択された遷移先に対応するiOS画面を提供します。
    ///
    /// 責務: 現在の遷移先を設定画面または識別用プレースホルダーへ振り分けます。
    @ViewBuilder
    var body: some View {
        if destination == .home {
            IOSHomeView(
                state: IOSHomeState(settingsState: settingsState),
                send: sendHomeAction
            )
        } else if destination == .settings {
            IOSSettingsView(
                state: settingsState,
                send: sendSettingsAction
            )
        } else {
            placeholder
        }
    }

    /// 未実装の遷移先を識別できるモバイル向けプレースホルダーです。
    private var placeholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                brandHeader

                VStack(alignment: .leading, spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))

                        Image(systemName: destination.systemImage)
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(.tint)
                    }
                    .frame(width: 82, height: 82)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(destination.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))

                        Text(destination.subtitle)
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("shell.destination.placeholder")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("ios-destination-\(destination.rawValue)")
    }

    /// 製品名とモバイル向けコンセプトを示すコンパクトなブランド表示です。
    private var brandHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.58)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.accentColor.opacity(0.28), radius: 12, y: 5)

                Image(systemName: "car.side.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("Project ZD8")
                    .font(.system(.headline, design: .rounded, weight: .bold))

                Text("ios.shell.tagline")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
