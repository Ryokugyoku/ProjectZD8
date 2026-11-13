#if os(iOS)
import SwiftUI

/// セッションの全属性・カウンタ・応答率・Raw の所在・アップロード状態を示す詳細画面です。
struct IOSLogSessionDetailView: View {
    let detail: LogHistorySessionDetail
    let send: (LogHistoryAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: InsightSpacing.lg) {
                analyzeButton
                overviewCard
                countersCard
                sourceCard
                storageCard
                actions
            }
            .frame(maxWidth: IOSAppShellMetrics.contentMaxWidth)
            .padding(.horizontal, InsightSpacing.screenGutter)
            .padding(.vertical, InsightSpacing.lg)
            .frame(maxWidth: .infinity)
        }
        .background(InsightBackground())
        .navigationTitle(Text("logs.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var row: LogHistorySessionRow { detail.row }

    private var overviewCard: some View {
        InsightCard(
            title: detail.vehicleName.map { Text(verbatim: $0) } ?? Text("logs.vehicle.unknown"),
            trailing: {
                HStack(spacing: InsightSpacing.xs) {
                    if row.isRecording { StatusBadge(Text("drive.phase.recording"), tone: .active, symbol: "record.circle") }
                    if row.isDemo { StatusBadge(Text("drive.demo"), tone: .warning) }
                }
            },
            content: {
                KeyValueRow(Text("logs.detail.startedAt"), value: Text(row.startedAt, format: .dateTime.year().month().day().hour().minute().second()))
                if let endedAt = row.endedAt {
                    KeyValueRow(Text("logs.detail.endedAt"), value: Text(endedAt, format: .dateTime.year().month().day().hour().minute().second()))
                }
                if let duration = row.durationText {
                    KeyValueRow(Text("logs.detail.duration"), value: Text(verbatim: duration), isNumeric: true)
                }
                if let key = row.endReasonKey {
                    KeyValueRow(Text("logs.detail.endReason"), value: Text(LocalizedStringKey(key)))
                }
                KeyValueRow(Text("logs.detail.distance"), value: row.distanceText.map { Text(verbatim: $0) } ?? Text("common.unavailable"), isNumeric: true)
                if let start = detail.odometerStartKilometers {
                    KeyValueRow(Text("logs.detail.odometerStart"), value: Text(verbatim: LogHistorySessionRow.distanceText(start)), isNumeric: true)
                }
                if let end = detail.odometerEndKilometers {
                    KeyValueRow(Text("logs.detail.odometerEnd"), value: Text(verbatim: LogHistorySessionRow.distanceText(end)), isNumeric: true)
                }
                if let key = detail.distanceSourceKey {
                    KeyValueRow(Text("logs.detail.distanceSource"), value: Text(LocalizedStringKey(key)))
                }
            }
        )
    }

    private var countersCard: some View {
        InsightCard(title: Text("logs.detail.counters")) {
            KeyValueRow(Text("logs.detail.samples"), value: Text(detail.sampleCount, format: .number), isNumeric: true)
            KeyValueRow(Text("logs.detail.responded"), value: Text(detail.respondedCount, format: .number), isNumeric: true)
            KeyValueRow(Text("logs.detail.noResponse"), value: Text(detail.noResponseCount, format: .number), isNumeric: true)
            KeyValueRow(Text("logs.detail.payload"), value: Text(verbatim: detail.payloadSizeText), isNumeric: true)
            LinearMeter(
                value: detail.responseRate,
                label: Text("logs.detail.responseRate"),
                valueText: detail.responseRateText.map { Text(verbatim: $0) }
            )
        }
    }

    private var sourceCard: some View {
        InsightCard(title: Text("logs.detail.source")) {
            KeyValueRow(Text("logs.detail.adapter"), value: Text(verbatim: detail.adapterName))
            KeyValueRow(Text("logs.detail.transport"), value: Text(LocalizedStringKey(detail.adapterTransportKey)))
            KeyValueRow(Text("logs.detail.platform"), value: Text(LocalizedStringKey(detail.platformKey)))
            KeyValueRow(Text("logs.detail.device"), value: Text(verbatim: detail.deviceName))
            KeyValueRow(Text("logs.detail.appVersion"), value: Text(verbatim: "\(detail.appVersion) (\(detail.appBuild))"), isNumeric: true)
            KeyValueRow(Text("logs.detail.pollingPolicy"), value: Text(detail.pollingPolicyVersion, format: .number), isNumeric: true)
        }
    }

    private var storageCard: some View {
        InsightCard(title: Text("logs.detail.storage")) {
            KeyValueRow(Text("logs.detail.rawLocation"), value: Text(LocalizedStringKey(row.rawLocation.nameKey)))
            KeyValueRow(Text("logs.detail.uploadState"), value: Text(LocalizedStringKey(row.uploadState.nameKey)))
            if let digest = detail.archiveDigest {
                KeyValueRow(Text("logs.detail.digest"), value: Text(verbatim: digest))
            }
        }
    }

    private var analyzeButton: some View {
        Button { send(.analysisRequested(row.id)) } label: {
            Label("logs.action.analyze", systemImage: "chart.xyaxis.line").frame(maxWidth: .infinity)
        }
        .buttonStyle(.insightPrimary)
        .disabled(row.isRecording)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: InsightSpacing.md) {
            if row.canFreeUpSpace {
                Button { send(.freeUpSpaceRequested(row.id)) } label: {
                    Label("logs.action.freeUp", systemImage: "internaldrive").frame(maxWidth: .infinity)
                }
                .buttonStyle(.insightSecondary)
            }
            Button { send(.deleteRequested(row.id)) } label: {
                Label("logs.action.delete", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .buttonStyle(.insightDestructive)
            .disabled(row.isRecording)
        }
    }
}
#endif
