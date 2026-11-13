#if os(macOS)
import SwiftUI

/// 車両を選び、その車両のセッションから分析対象を選ぶ一覧です。
struct MacOSAnalysisSessionList: View {
    let state: AnalysisState
    let send: (AnalysisAction) -> Void

    /// 責務: 車両の選択と、セッション一覧を描画します。
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: vehicleBinding) {
                ForEach(state.vehicles) { vehicle in
                    Text(vehicle.name).tag(Optional(vehicle.id))
                }
            } label: {
                Text("analysis.mac.vehicle")
            }
            .disabled(state.vehicles.isEmpty)
            if state.pickerPurpose == .addComparison {
                Label("analysis.mac.pickCompare", systemImage: "square.on.square")
                    .font(.callout)
                    .foregroundStyle(.tint)
            }
            if state.sessionOptions.isEmpty {
                ContentUnavailableView {
                    Label("analysis.mac.noSessions", systemImage: "waveform.path.ecg")
                }
            } else {
                List(state.sessionOptions) { option in
                    Button { choose(option) } label: { row(option) }
                        .buttonStyle(.plain)
                        .listRowBackground(isLoaded(option) ? Color.accentColor.opacity(0.15) : Color.clear)
                        .contextMenu {
                            Button("analysis.mac.addComparison") { send(.addComparisonSession(option.id)) }
                                .disabled(state.isAtSessionLimit || isLoaded(option))
                        }
                }
            }
        }
        .padding(12)
    }

    /// 責務: 車両選択の双方向束縛を返します。
    private var vehicleBinding: Binding<VehicleID?> {
        Binding(
            get: { state.selectedVehicleID },
            set: { if let id = $0 { send(.selectVehicle(id)) } }
        )
    }

    /// 責務: 目的に応じて、セッションを開くか比較へ追加します。
    private func choose(_ option: AnalysisSessionOption) {
        if state.pickerPurpose == .addComparison {
            send(.addComparisonSession(option.id))
        } else {
            send(.openSession(option.id))
        }
    }

    /// 責務: 既に読み込み済みのセッションかどうかを返します。
    private func isLoaded(_ option: AnalysisSessionOption) -> Bool {
        state.loadedSessions.contains { $0.id == option.id }
    }

    /// 責務: 1件のセッションの行を描画します。
    private func row(_ option: AnalysisSessionOption) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(option.startedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.body.weight(.medium))
                if option.isDemo {
                    Text("analysis.mac.demo").font(.caption2).padding(.horizontal, 5).background(.quaternary, in: Capsule())
                }
                Spacer(minLength: 0)
                if option.rawAvailability == .cloudOnly {
                    Image(systemName: "icloud").foregroundStyle(.secondary).help(Text("analysis.mac.cloudOnly"))
                }
            }
            HStack(spacing: 8) {
                if let duration = option.durationSeconds {
                    Text(Duration.seconds(duration), format: .time(pattern: .minuteSecond))
                }
                Text("analysis.mac.sampleCount \(option.sampleCount)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, MacOSAnalysisMetrics.rowVerticalPadding)
        .contentShape(Rectangle())
    }
}
#endif
