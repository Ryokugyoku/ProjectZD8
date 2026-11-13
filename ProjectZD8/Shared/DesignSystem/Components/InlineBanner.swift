import SwiftUI

/// 画面内に差し込む通知帯(情報・警告・エラー)。任意のアクションボタン付き。
struct InlineBanner: View {
    /// バナーの種類。
    enum Kind {
        case info
        case warning
        case error

        /// 種類に対応するトーン。
        var tone: StatusTone {
            switch self {
            case .info: .active
            case .warning: .warning
            case .error: .critical
            }
        }

        /// 種類に対応するシンボル。
        var symbol: String {
            switch self {
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }
    }

    private let kind: Kind
    private let title: Text?
    private let message: Text
    private let action: InsightAction?

    /// バナーを作る。
    ///
    /// 責務: 種類・文言・任意アクションを保持する。
    init(_ kind: Kind, title: Text? = nil, message: Text, action: InsightAction? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: InsightSpacing.md) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.tone.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: InsightSpacing.xs) {
                if let title { title.font(InsightTypography.sectionTitle) }
                message.font(InsightTypography.caption).foregroundStyle(.secondary)
                if let action {
                    Button(action: action.handler) { action.title }
                        .buttonStyle(.plain)
                        .font(InsightTypography.label)
                        .foregroundStyle(kind.tone.color)
                        .frame(minHeight: InsightSpacing.minimumHitTarget - 12, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(InsightSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: InsightRadius.sm, style: .continuous)
                .fill(kind.tone.color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: InsightRadius.sm, style: .continuous)
                .strokeBorder(kind.tone.color.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

#Preview("Light") {
    VStack(spacing: 12) {
        InlineBanner(.info, message: Text(verbatim: "Adapter found nearby."))
        InlineBanner(.warning, title: Text(verbatim: "Low voltage"), message: Text(verbatim: "Battery is at 11.8 V."),
                     action: InsightAction(Text(verbatim: "Details")) {})
        InlineBanner(.error, message: Text(verbatim: "Connection lost."), action: InsightAction(Text(verbatim: "Retry")) {})
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VStack(spacing: 12) {
        InlineBanner(.info, message: Text(verbatim: "Adapter found nearby."))
        InlineBanner(.error, title: Text(verbatim: "Failed"), message: Text(verbatim: "Connection lost."))
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.dark)
}
