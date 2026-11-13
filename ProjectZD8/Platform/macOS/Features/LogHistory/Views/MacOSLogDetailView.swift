#if os(macOS)
import SwiftUI

/// 選択したセッションの全属性・カウンタ・Raw の所在・アップロード状態と、分析 / 空き容量確保 / 削除の操作。
struct MacOSLogDetailView: View {
    let detail: LogHistorySessionDetail
    let send: (LogHistoryAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: InsightSpacing.lg) {
                header
                actions
                InsightCard(title: Text("history.detail.section.session")) {
                    VStack(spacing: InsightSpacing.sm) {
                        KeyValueRow(Text("history.detail.started"), value: Text(detail.row.startedAt, format: dateStyle))
                        KeyValueRow(Text("history.detail.ended"), value: detail.row.endedAt.map { Text($0, format: dateStyle) } ?? Text("history.detail.notEnded"))
                        KeyValueRow(Text("history.detail.duration"), value: text(detail.row.durationText), isNumeric: true)
                        KeyValueRow(Text("history.detail.distance"), value: text(detail.row.distanceText), isNumeric: true)
                        KeyValueRow(Text("history.detail.endReason"), value: detail.row.endReasonKey.map { Text(LocalizedStringKey($0)) } ?? Text(verbatim: "—"))
                        KeyValueRow(Text("history.detail.odometerStart"), value: text(detail.odometerStartKilometers.map(LogHistorySessionRow.distanceText)), isNumeric: true)
                        KeyValueRow(Text("history.detail.odometerEnd"), value: text(detail.odometerEndKilometers.map(LogHistorySessionRow.distanceText)), isNumeric: true)
                        KeyValueRow(Text("history.detail.distanceSource"), value: detail.distanceSourceKey.map { Text(LocalizedStringKey($0)) } ?? Text(verbatim: "—"))
                    }
                }
                InsightCard(title: Text("history.detail.section.counters")) {
                    VStack(spacing: InsightSpacing.sm) {
                        KeyValueRow(Text("history.detail.samples"), value: Text(verbatim: detail.sampleCount.formatted()), isNumeric: true)
                        KeyValueRow(Text("history.detail.responded"), value: Text(verbatim: detail.respondedCount.formatted()), isNumeric: true)
                        KeyValueRow(Text("history.detail.noResponse"), value: Text(verbatim: detail.noResponseCount.formatted()), isNumeric: true)
                        KeyValueRow(Text("history.detail.responseRate"), value: text(detail.responseRateText), isNumeric: true)
                    }
                }
                InsightCard(title: Text("history.detail.section.storage")) {
                    VStack(spacing: InsightSpacing.sm) {
                        KeyValueRow(Text("history.detail.rawLocation"), value: Text(LocalizedStringKey(detail.row.rawLocation.nameKey)))
                        KeyValueRow(Text("history.detail.upload"), value: Text(LocalizedStringKey(detail.row.uploadState.nameKey)))
                        KeyValueRow(Text("history.detail.size"), value: Text(verbatim: detail.payloadSizeText), isNumeric: true)
                        if let digest = detail.archiveDigest {
                            KeyValueRow(Text("history.detail.digest"), value: Text(verbatim: String(digest.prefix(12))), isNumeric: true)
                        }
                    }
                }
                InsightCard(title: Text("history.detail.section.source")) {
                    VStack(spacing: InsightSpacing.sm) {
                        KeyValueRow(Text("history.detail.adapter"), value: Text(verbatim: detail.adapterName))
                        KeyValueRow(Text("history.detail.transport"), value: Text(LocalizedStringKey(detail.adapterTransportKey)))
                        KeyValueRow(Text("history.detail.platform"), value: Text(LocalizedStringKey(detail.platformKey)))
                        KeyValueRow(Text("history.detail.device"), value: Text(verbatim: detail.deviceName))
                        KeyValueRow(Text("history.detail.app"), value: Text(verbatim: "\(detail.appVersion) (\(detail.appBuild))"), isNumeric: true)
                        KeyValueRow(Text("history.detail.pollingPolicy"), value: Text(verbatim: String(detail.pollingPolicyVersion)), isNumeric: true)
                    }
                }
            }
            .padding(InsightSpacing.lg)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.xs) {
            HStack(spacing: InsightSpacing.sm) {
                (detail.vehicleName.map { Text(verbatim: $0) } ?? Text("history.group.unknownVehicle"))
                    .font(InsightTypography.screenTitle)
                if detail.row.isRecording { StatusBadge(Text("history.badge.recording"), tone: .critical, symbol: "record.circle") }
                if detail.row.isDemo { StatusBadge(Text("drive.badge.demo"), tone: .warning, symbol: "sparkles") }
                if detail.row.wasInterrupted { StatusBadge(Text("history.badge.interrupted"), tone: .warning, symbol: "exclamationmark.triangle") }
            }
            Text(detail.row.startedAt, format: dateStyle)
                .font(InsightTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: InsightSpacing.sm) {
            Button {
                send(.analysisRequested(detail.row.id))
            } label: {
                Label("history.analysis.button", systemImage: "chart.xyaxis.line")
            }
            .buttonStyle(.insightPrimary)
            .disabled(detail.row.isRecording)

            Button {
                send(.freeUpSpaceRequested(detail.row.id))
            } label: {
                Label("history.free_up.button", systemImage: "externaldrive.badge.minus")
            }
            .buttonStyle(.insightSecondary)
            .disabled(!detail.row.canFreeUpSpace)

            Button(role: .destructive) {
                send(.deleteRequested(detail.row.id))
            } label: {
                Label("history.delete.button", systemImage: "trash")
            }
            .buttonStyle(.insightDestructive)
            .disabled(detail.row.isRecording)

            Spacer()
            Button {
                send(.detailClosed)
            } label: {
                Label("common.close", systemImage: "xmark")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    private var dateStyle: Date.FormatStyle { .dateTime.year().month().day().hour().minute().second() }

    /// 値が無い時は欠測として「—」を出す。
    private func text(_ value: String?) -> Text {
        value.map { Text(verbatim: $0) } ?? Text(verbatim: "—")
    }
}
#endif
