#if os(iOS)
import SwiftUI

/// iOSでPID分類の代表値と分類内の全現在値を描画します。
struct IOSLiveTelemetryView: View {
    /// Applicationが公開するPID読取状態です。
    let state: LiveTelemetryState
    /// PID読取操作の通知先です。
    let send: (LiveTelemetryAction) -> Void

    /// モバイル専用の分類別PID読取表示を提供します。
    ///
    /// 責務: LiveTelemetry状態をiOS専用の分類一覧と分類詳細へ変換します。
    var body: some View {
        NavigationStack {
            List {
                if state.phase == .reading { ProgressView("telemetry.status.reading") }
                if state.phase == .stopping { ProgressView("telemetry.status.stopping") }
                if let failureKey = state.failureKey {
                    Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                ForEach(OBDPIDCategory.allCases, id: \.self) { category in
                    let categorySamples = samples(in: category)
                    if !categorySamples.isEmpty {
                        NavigationLink {
                            List(categorySamples) { sample in
                                LabeledContent(LocalizedStringKey(sample.nameKey)) {
                                    Text(formatted(sample))
                                }
                            }
                            .navigationTitle(LocalizedStringKey(category.nameKey))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(LocalizedStringKey(category.nameKey))
                                    .font(.headline)
                                if let representative = representative(in: categorySamples, category: category) {
                                    Text(LocalizedStringKey(representative.nameKey))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(formatted(representative))
                                        .font(.title3.monospacedDigit().weight(.semibold))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                if state.phase == .loaded {
                    Label("telemetry.status.streaming", systemImage: "waveform.path.ecg")
                        .foregroundStyle(.green)
                } else if state.phase == .failed {
                    Button("telemetry.retry") { send(.retryRequested) }
                } else if state.phase == .idle {
                    Text("telemetry.status.waiting_for_connection")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("telemetry.title")
        }
        .accessibilityIdentifier("ios-live-telemetry")
    }

    /// 指定分類に含まれる現在サンプルだけを返します。
    ///
    /// 責務: Applicationの全PID状態を1件のiOS表示分類へ射影します。
    /// - Parameter category: 抽出するPID分類。
    /// - Returns: 元の取得順を保った分類内サンプル。
    private func samples(in category: OBDPIDCategory) -> [OBDPIDSample] {
        state.samples.filter { OBDPIDCategory.category(for: $0.request) == category }
    }

    /// 分類カードへ表示する現在サンプルを選びます。
    ///
    /// 責務: 分類内サンプルから代表PIDを優先した1件を選択します。
    /// - Parameters:
    ///   - samples: 分類内の応答済みサンプル。
    ///   - category: 代表PIDを定義する分類。
    /// - Returns: 代表PIDのサンプル、未応答時は分類の先頭サンプル。
    private func representative(
        in samples: [OBDPIDSample],
        category: OBDPIDCategory
    ) -> OBDPIDSample? {
        samples.first(where: { $0.request == category.representativeRequest }) ?? samples.first
    }

    /// PID数値と単位を1行表示へ整形します。
    ///
    /// 責務: 1件のPIDサンプルをiOS用の単位付き現在値文字列へ変換します。
    /// - Parameter sample: 表示するPIDサンプル。
    /// - Returns: 小数2桁以内の数値と単位。
    private func formatted(_ sample: OBDPIDSample) -> String {
        "\(sample.value.formatted(.number.precision(.fractionLength(0...2)))) \(sample.unit)"
    }
}
#endif
