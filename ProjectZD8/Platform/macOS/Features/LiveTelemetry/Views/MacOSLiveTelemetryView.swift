#if os(macOS)
import SwiftUI

/// macOSで分類別の代表PIDと分類内の全現在値を描画します。
struct MacOSLiveTelemetryView: View {
    /// Applicationが公開するPID読取状態です。
    let state: LiveTelemetryState
    /// PID読取操作の通知先です。
    let send: (LiveTelemetryAction) -> Void
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// 現在詳細表示しているPID分類です。
    @State private var selectedCategory: OBDPIDCategory = .engine
    /// 詳細Popoverへ表示する現在のPIDです。
    @State private var helpSample: OBDPIDSample?

    /// PID読取操作、分類選択、数値、失敗に対応するmacOS表示を提供します。
    ///
    /// 責務: LiveTelemetry状態をmacOS専用の分類選択とPID詳細へ変換します。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24 * metrics.scale) {
                Text("telemetry.eyebrow")
                    .font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded))
                    .tracking(1.7 * metrics.scale)
                    .foregroundStyle(.tint)
                Text("telemetry.title")
                    .font(.system(size: 32 * metrics.scale, weight: .bold, design: .rounded))
                Text("telemetry.subtitle")
                    .foregroundStyle(.secondary)

                if state.phase == .reading {
                    ProgressView("telemetry.status.reading")
                } else if state.phase == .stopping {
                    ProgressView("telemetry.status.stopping")
                } else if let failureKey = state.failureKey {
                    Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                if !state.samples.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10 * metrics.scale) {
                            ForEach(availableCategories, id: \.self) { category in
                                Button {
                                    selectedCategory = category
                                } label: {
                                    VStack(alignment: .leading, spacing: 5 * metrics.scale) {
                                        Text(LocalizedStringKey(category.nameKey))
                                            .font(.system(size: 13 * metrics.scale, weight: .semibold, design: .rounded))
                                        if let sample = representative(in: samples(in: category), category: category) {
                                            Text(formatted(sample))
                                                .font(.system(size: 18 * metrics.scale, weight: .bold, design: .rounded).monospacedDigit())
                                        }
                                    }
                                    .padding(.horizontal, 16 * metrics.scale)
                                    .frame(minHeight: 56 * metrics.scale, alignment: .leading)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(selectedCategory == category ? .accentColor : .secondary.opacity(0.18))
                                .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
                            }
                        }
                    }

                    Text(LocalizedStringKey(selectedCategory.nameKey))
                        .font(.system(size: 21 * metrics.scale, weight: .bold, design: .rounded))

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220 * metrics.scale), spacing: 18 * metrics.scale)],
                        spacing: 18 * metrics.scale
                    ) {
                        ForEach(samples(in: selectedCategory)) { sample in
                            VStack(alignment: .leading, spacing: 10 * metrics.scale) {
                                HStack {
                                    Text(LocalizedStringKey(sample.nameKey)).foregroundStyle(.secondary)
                                    if let modelCode = sample.vehicleModelCode {
                                        VehicleModelBadge(modelCode: modelCode)
                                            .scaleEffect(0.74)
                                            .frame(width: 28, height: 28)
                                    }
                                    Spacer()
                                    Button { helpSample = sample } label: {
                                        Image(systemName: "questionmark.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .help(Text(LocalizedStringKey(sample.summaryKey)))
                                    .accessibilityLabel("telemetry.help.open")
                                    .popover(isPresented: Binding(
                                        get: { helpSample?.id == sample.id },
                                        set: { if !$0 { helpSample = nil } }
                                    )) {
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text(LocalizedStringKey(sample.nameKey)).font(.headline)
                                            helpRow("telemetry.help.summary", valueKey: sample.summaryKey)
                                            helpRow("telemetry.help.high", valueKey: sample.highValueKey)
                                            helpRow("telemetry.help.low", valueKey: sample.lowValueKey)
                                            helpRow("telemetry.help.correlation", valueKey: sample.correlationKey)
                                        }
                                        .padding(18)
                                        .frame(width: 360)
                                    }
                                }
                                Text(sample.value, format: .number.precision(.fractionLength(0...2)))
                                    .font(.system(size: 32 * metrics.scale, weight: .bold, design: .rounded).monospacedDigit())
                                Text(sample.unit).foregroundStyle(.secondary)
                            }
                            .padding(18 * metrics.scale)
                            .frame(maxWidth: .infinity, minHeight: 132 * metrics.scale, alignment: .leading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18 * metrics.scale))
                        }
                    }
                }

                if state.phase == .loaded {
                    Label(
                        state.acquisitionMode == .brzBetaPeriodic
                            ? "telemetry.status.brz_beta_periodic"
                            : "telemetry.status.streaming",
                        systemImage: "waveform.path.ecg"
                    )
                        .foregroundStyle(.green)
                } else if state.phase == .failed {
                    Button("telemetry.retry") { send(.retryRequested) }
                        .buttonStyle(.borderedProminent)
                } else if state.phase == .idle {
                    Text("telemetry.status.waiting_for_connection")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(32 * metrics.scale)
            .frame(maxWidth: 1_180 * metrics.scale)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("macos-live-telemetry")
        .alert(
            "telemetry.brz_beta.warning.title",
            isPresented: betaConsentIsPresented
        ) {
            Button("telemetry.brz_beta.warning.use_standard", role: .cancel) {
                send(.brzBetaDeclined)
            }
            Button("telemetry.brz_beta.warning.accept", role: .destructive) {
                send(.brzBetaAccepted)
            }
        } message: {
            Text("telemetry.brz_beta.warning.message")
        }
        .onChange(of: availableCategories) { _, categories in
            if !categories.contains(selectedCategory), let first = categories.first {
                selectedCategory = first
            }
        }
    }

    /// BRZ Betaの危険性確認を表示するBindingです。
    private var betaConsentIsPresented: Binding<Bool> {
        Binding(
            get: { state.phase == .awaitingBRZBetaConsent },
            set: { _ in }
        )
    }

    /// 応答済みサンプルを持つ分類を表示順で返します。
    private var availableCategories: [OBDPIDCategory] {
        OBDPIDCategory.allCases.filter { !samples(in: $0).isEmpty }
    }

    /// 指定分類に含まれる現在サンプルだけを返します。
    ///
    /// 責務: Applicationの全PID状態を1件のmacOS表示分類へ射影します。
    /// - Parameter category: 抽出するPID分類。
    /// - Returns: 元の取得順を保った分類内サンプル。
    private func samples(in category: OBDPIDCategory) -> [OBDPIDSample] {
        state.samples.filter { OBDPIDCategory.category(for: $0.request) == category }
    }

    /// 分類ボタンへ表示する現在サンプルを選びます。
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
    /// 責務: 1件のPIDサンプルをmacOS用の単位付き現在値文字列へ変換します。
    /// - Parameter sample: 表示するPIDサンプル。
    /// - Returns: 小数2桁以内の数値と単位。
    private func formatted(_ sample: OBDPIDSample) -> String {
        "\(sample.value.formatted(.number.precision(.fractionLength(0...2)))) \(sample.unit)"
    }

    /// PIDヘルプの見出しと説明を1組表示します。
    ///
    /// 責務: 1件のヘルプ項目をmacOS Popover用の見出し付き本文へ変換します。
    /// - Parameters:
    ///   - titleKey: 見出しのローカライズキー。
    ///   - valueKey: 本文のローカライズキー。
    /// - Returns: 見出しと説明を縦に並べた表示。
    private func helpRow(_ titleKey: String, valueKey: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(titleKey)).font(.caption.bold()).foregroundStyle(.secondary)
            Text(LocalizedStringKey(valueKey))
        }
    }
}
#endif
