#if os(iOS)
import SwiftUI

/// 接続から準備までの進行を、段階の一覧で示すカードです。
struct IOSDriveProgressCard: View {
    let drive: DriveSessionState
    let sendDrive: (DriveSessionAction) -> Void

    /// 進行を示す段階の並びです。
    private let steps: [(phase: DriveSessionPhase, key: String)] = [
        (.connecting, "drive.phase.connecting"),
        (.identifying, "drive.phase.identifying"),
        (.preparing, "drive.phase.preparing")
    ]

    var body: some View {
        InsightCard(title: Text(LocalizedStringKey(drive.phase.localizationKey))) {
            if let adapter = drive.adapter {
                HStack(spacing: InsightSpacing.sm) {
                    Image(systemName: adapter.transport.iosSymbolName).accessibilityHidden(true)
                    Text(verbatim: adapter.displayName)
                }
                .font(InsightTypography.caption)
                .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: InsightSpacing.md) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    stepRow(index: index, key: step.key)
                }
            }
            if drive.phase != .stopping {
                Button { sendDrive(.stopRequested) } label: { Text("drive.cancel").frame(maxWidth: .infinity) }
                    .buttonStyle(.insightSecondary)
            } else {
                HStack(spacing: InsightSpacing.sm) {
                    ProgressView()
                    Text("drive.phase.stopping").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 現在の段階より前を完了、現在を進行中、後を待機として行を描きます。
    private func stepRow(index: Int, key: String) -> some View {
        let current = currentIndex
        let isDone = current.map { index < $0 } ?? false
        let isCurrent = current == index
        return HStack(spacing: InsightSpacing.md) {
            Group {
                if isCurrent {
                    ProgressView()
                } else {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isDone ? InsightPalette.positive : InsightPalette.neutral)
                }
            }
            .frame(width: InsightSpacing.xl)
            Text(LocalizedStringKey(key))
                .font(InsightTypography.body)
                .foregroundStyle(isCurrent || isDone ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .updatesFrequently : [])
    }

    /// 現在の段階が一覧の何番目かです。車両登録待ちは識別の続きとして扱い、停止中は一覧の外です。
    private var currentIndex: Int? {
        switch drive.phase {
        case .connecting: 0
        case .identifying, .awaitingVehicleRegistration: 1
        case .preparing: 2
        case .idle, .recording, .stopping: nil
        }
    }
}
#endif
