#if os(iOS)
import SwiftUI

/// 分析するセッションを選ぶシートです。比較用の追加にも使います。
struct IOSAnalysisSessionSheet: View {
    let state: AnalysisState
    let send: (AnalysisAction) -> Void

    /// 責務: 車両のセッションを一覧し、選択に応じて開く・比較へ追加する操作を送ります。
    var body: some View {
        NavigationStack {
            List(state.sessionOptions) { option in
                Button { choose(option) } label: { row(option) }
                    .tint(.primary)
                    .listRowBackground(isLoaded(option) ? Color.accentColor.opacity(0.15) : nil)
            }
            .overlay {
                if state.sessionOptions.isEmpty {
                    ContentUnavailableView {
                        Label("analysis.ios.noSessions", systemImage: "waveform.path.ecg")
                    }
                }
            }
            .navigationTitle(state.pickerPurpose == .addComparison ? Text("analysis.ios.pickCompare") : Text("analysis.ios.sessions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("analysis.ios.cancel") { send(.dismissSessionPicker) }
                }
            }
        }
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
                    Text("analysis.ios.demo").font(.caption2).padding(.horizontal, 5).background(.quaternary, in: Capsule())
                }
                Spacer(minLength: 0)
                if option.rawAvailability == .cloudOnly {
                    Image(systemName: "icloud").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                if let duration = option.durationSeconds {
                    Text(Duration.seconds(duration), format: .time(pattern: .minuteSecond))
                }
                Text("analysis.ios.sampleCount \(option.sampleCount)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, IOSAnalysisMetrics.rowVerticalPadding)
    }
}
#endif
