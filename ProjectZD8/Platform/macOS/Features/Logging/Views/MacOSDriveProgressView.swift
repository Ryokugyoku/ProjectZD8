#if os(macOS)
import SwiftUI

/// 接続開始から記録開始までの進行(接続 → 識別 → 準備)を示すカード。
struct MacOSDriveProgressView: View {
    let phase: DriveSessionPhase
    let adapter: AdapterDescriptor?

    private enum Step: Int, CaseIterable {
        case connecting, identifying, preparing

        var titleKey: LocalizedStringKey {
            switch self {
            case .connecting: "drive.phase.connecting"
            case .identifying: "drive.phase.identifying"
            case .preparing: "drive.phase.preparing"
            }
        }
    }

    /// 現在進行中のステップ。登録待ちは識別と準備の間として扱う。
    private var currentIndex: Int? {
        switch phase {
        case .connecting: Step.connecting.rawValue
        case .identifying: Step.identifying.rawValue
        case .awaitingVehicleRegistration: Step.identifying.rawValue
        case .preparing: Step.preparing.rawValue
        case .idle, .recording, .stopping: nil
        }
    }

    var body: some View {
        InsightCard(title: Text(LocalizedStringKey(phase.localizationKey))) {
            VStack(alignment: .leading, spacing: InsightSpacing.md) {
                if let adapter {
                    HStack(spacing: InsightSpacing.sm) {
                        Image(systemName: adapter.transport.macOSSymbol).accessibilityHidden(true)
                        Text(verbatim: adapter.displayName)
                    }
                    .font(InsightTypography.caption)
                    .foregroundStyle(.secondary)
                }
                ForEach(Step.allCases, id: \.self) { step in
                    stepRow(step)
                }
            }
        }
    }

    private func stepRow(_ step: Step) -> some View {
        let state = stepState(step)
        return HStack(spacing: InsightSpacing.sm) {
            switch state {
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(InsightPalette.positive)
            case .active:
                ProgressView().controlSize(.small)
            case .pending:
                Image(systemName: "circle").foregroundStyle(.tertiary)
            }
            Text(step.titleKey)
                .foregroundStyle(state == .pending ? .secondary : .primary)
        }
        .font(InsightTypography.body)
        .accessibilityElement(children: .combine)
    }

    private enum StepState { case done, active, pending }

    private func stepState(_ step: Step) -> StepState {
        guard let currentIndex else { return .pending }
        if step.rawValue < currentIndex { return .done }
        return step.rawValue == currentIndex ? .active : .pending
    }
}
#endif
