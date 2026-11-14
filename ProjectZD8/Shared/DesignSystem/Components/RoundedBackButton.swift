import SwiftUI

/// 角丸の面に左向き山形を置いた、画面ヘッダー用の戻るボタンです。
struct RoundedBackButton: View {
    /// アクセシビリティラベルとヘルプに使うローカライズキーです。
    let accessibilityLabelKey: LocalizedStringKey
    /// UI テスト用のアクセシビリティ識別子です。
    let identifier: String
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 押下時の操作です。
    let action: () -> Void

    /// 戻るボタンを描画します。
    ///
    /// 責務: 倍率に応じた 44pt 基準の角丸ボタンへ、ラベル、識別子、操作を接続します。
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14 * scale, weight: .bold))
                .frame(width: 44 * scale, height: 44 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        }
        .accessibilityLabel(Text(accessibilityLabelKey))
        .accessibilityIdentifier(identifier)
        .help(Text(accessibilityLabelKey))
    }
}
