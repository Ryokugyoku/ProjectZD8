#if os(iOS)
import SwiftUI

/// iPhone向けに運転中の主要値、BRZ専用値、補助値の順でリアルタイムPIDを描画します。
struct IOSLiveTelemetryView: View {
    /// Applicationが公開するPID読取状態です。
    let state: LiveTelemetryState
    /// PID読取操作の通知先です。
    let send: (LiveTelemetryAction) -> Void
    /// ヘルプシートへ表示する現在のPIDです。
    @State private var helpSample: OBDPIDSample?

    /// モバイル専用の優先度付きコックピット表示を提供します。
    ///
    /// 責務: LiveTelemetry状態を主要値が最初に読めるiOS専用画面へ変換します。
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    hero
                    operationalState
                    if !state.samples.isEmpty {
                        primaryDashboard
                        if !vehicleSpecificSamples.isEmpty { brzSection }
                        categorySection
                    } else if state.phase == .idle {
                        waitingState
                    }
                    if state.phase == .failed { retryButton }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .background(telemetryBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $helpSample) { sample in helpSheet(sample) }
        .accessibilityIdentifier("ios-live-telemetry")
    }

    /// 画面全体へ接続履歴と共通する抑制された奥行きを与える背景です。
    private var telemetryBackground: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            RadialGradient(colors: [Color.cyan.opacity(0.12), .clear], center: .topTrailing, startRadius: 10, endRadius: 430)
        }
    }

    /// 画面の目的と現在の取得件数を示す上部カードです。
    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 58, height: 58)
                    .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("telemetry.eyebrow").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.cyan)
                    Text("telemetry.title").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("telemetry.subtitle").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if state.supportedPIDCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    Text(state.supportedPIDCount, format: .number)
                        .font(.title2.monospacedDigit().weight(.bold))
                    Text("telemetry.status.responding_count")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if vehicleSpecificSamples.isEmpty == false {
                        Label("BRZ", systemImage: "sparkles").font(.caption.weight(.bold)).foregroundStyle(.cyan)
                    }
                }
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }

    /// 通信中、探索中、停止中、失敗の現在状態を表示します。
    @ViewBuilder private var operationalState: some View {
        switch state.phase {
        case .reading:
            statusBanner("telemetry.status.reading", symbol: "dot.radiowaves.left.and.right", color: .cyan, showsProgress: true)
        case .stopping:
            statusBanner("telemetry.status.stopping", symbol: "stop.circle", color: .orange, showsProgress: true)
        case .loaded:
            statusBanner(
                "telemetry.status.polling",
                symbol: "waveform.path.ecg",
                color: .green,
                showsProgress: false
            )
        case .failed:
            statusBanner(state.failureKey ?? "telemetry.error.read_failed", symbol: "exclamationmark.triangle.fill", color: .orange, showsProgress: false)
        case .idle:
            EmptyView()
        }
    }

    /// 状態キーを一貫したライブ表示へ変換します。
    ///
    /// 責務: 1件の取得状態を色、シンボル、任意の進捗表示を持つバナーへ変換します。
    /// - Parameters:
    ///   - key: 表示するローカライズキー。
    ///   - symbol: 状態を補助するSF Symbol名。
    ///   - color: 状態のアクセント色。
    ///   - showsProgress: 未完了処理を示す進捗表示を付ける場合は `true`。
    /// - Returns: 取得状態を表す横長バナー。
    private func statusBanner(_ key: String, symbol: String, color: Color, showsProgress: Bool) -> some View {
        HStack(spacing: 12) {
            if showsProgress { ProgressView().tint(color) } else { Image(systemName: symbol).foregroundStyle(color) }
            Text(LocalizedStringKey(key)).font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(minHeight: 50)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(color.opacity(0.18)) }
    }

    /// 回転数と車速を最優先に大きく表示します。
    private var primaryDashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("telemetry.section.now", symbol: "speedometer")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(primarySamples) { sample in primaryCard(sample) }
            }
        }
    }

    /// 主要PIDを瞬時に読める大型数値カードとして描画します。
    ///
    /// 責務: 1件の主要PIDを名称、現在値、単位、観測状態を持つカードへ変換します。
    /// - Parameter sample: 表示する主要PIDサンプル。
    /// - Returns: iPhone用の主要値カード。
    private func primaryCard(_ sample: OBDPIDSample) -> some View {
        Button { helpSample = sample } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: primarySymbol(for: sample.request)).foregroundStyle(.cyan)
                    Spacer()
                    Image(systemName: "info.circle").foregroundStyle(.tertiary)
                }
                Text(sample.value, format: .number.precision(.fractionLength(0...1)))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.65).lineLimit(1)
                Text(sample.unit).font(.caption.monospaced().weight(.semibold)).foregroundStyle(.cyan)
                Text(LocalizedStringKey(sample.nameKey)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(17).frame(maxWidth: .infinity, minHeight: 172, alignment: .leading)
            .background(LinearGradient(colors: [Color.cyan.opacity(0.14), Color.primary.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.cyan.opacity(0.2)) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(sample.nameKey)))
        .accessibilityValue(formatted(sample))
    }

    /// BRZ車種専用PIDを標準値から区別して表示します。
    private var brzSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("telemetry.section.brz", symbol: "car.side.fill")
                Spacer()
                if let modelCode = vehicleSpecificSamples.first?.vehicleModelCode { VehicleModelBadge(modelCode: modelCode) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(vehicleSpecificSamples) { sample in compactCard(sample, tint: .cyan) }
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.cyan.opacity(0.22)) }
    }

    /// 全応答値へ分類単位で到達できる補助領域です。
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("telemetry.section.all", symbol: "square.grid.2x2")
            ForEach(availableCategories, id: \.self) { category in
                NavigationLink { categoryDetail(category) } label: { categoryCard(category) }
                    .buttonStyle(.plain)
            }
        }
    }

    /// 1分類の代表値と収録数を遷移カードとして描画します。
    ///
    /// 責務: 1件のPID分類を代表値付きの詳細導線へ変換します。
    /// - Parameter category: 表示するPID分類。
    /// - Returns: 分類詳細へ遷移する横長カード。
    private func categoryCard(_ category: OBDPIDCategory) -> some View {
        let values = samples(in: category)
        return HStack(spacing: 14) {
            Image(systemName: categorySymbol(category)).font(.title3.weight(.semibold)).foregroundStyle(.tint)
                .frame(width: 46, height: 46).background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(category.nameKey)).font(.headline)
                Text(values.count, format: .number).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            if let sample = representative(in: values, category: category) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(sample.value, format: .number.precision(.fractionLength(0...1))).font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                    Text(sample.unit).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(15).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.07)) }
    }

    /// 1分類に含まれる現在値をカード一覧で表示します。
    ///
    /// 責務: 1件のPID分類を全現在値へ展開します。
    /// - Parameter category: 展開するPID分類。
    /// - Returns: 分類内の全サンプルを含む詳細画面。
    private func categoryDetail(_ category: OBDPIDCategory) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(samples(in: category)) { sample in compactCard(sample, tint: sample.vehicleModelCode == nil ? .accentColor : .cyan) }
            }.padding(18)
        }
        .background(telemetryBackground.ignoresSafeArea())
        .navigationTitle(LocalizedStringKey(category.nameKey))
    }

    /// 補助PIDを情報操作付きの小型カードとして描画します。
    ///
    /// 責務: 1件のPIDサンプルを名称と単位付き現在値を持つ補助カードへ変換します。
    /// - Parameters:
    ///   - sample: 表示するPIDサンプル。
    ///   - tint: 値と識別子へ使用する色。
    /// - Returns: PID説明を開ける小型カード。
    private func compactCard(_ sample: OBDPIDSample, tint: Color) -> some View {
        Button { helpSample = sample } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(LocalizedStringKey(sample.nameKey)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 4)
                    Image(systemName: "info.circle").foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(sample.value, format: .number.precision(.fractionLength(0...2))).font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                    Text(sample.unit).font(.caption.monospaced()).foregroundStyle(tint)
                }
            }
            .padding(15).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }.buttonStyle(.plain)
    }

    /// 未接続時の次の操作を表示します。
    private var waitingState: some View {
        ContentUnavailableView("telemetry.status.waiting_for_connection", systemImage: "cable.connector")
            .padding(30).frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// 失敗後の再取得操作です。
    private var retryButton: some View {
        Button { send(.retryRequested) } label: { Label("telemetry.retry", systemImage: "arrow.clockwise") }
            .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
    }

    /// ローカライズ済みセクション見出しを生成します。
    ///
    /// 責務: 1件の見出しキーとシンボルを同じ視覚階層へ変換します。
    /// - Parameters:
    ///   - key: 見出しのローカライズキー。
    ///   - symbol: 見出しを補助するSF Symbol名。
    /// - Returns: セクション見出し。
    private func sectionHeader(_ key: String, symbol: String) -> some View {
        Label(LocalizedStringKey(key), systemImage: symbol).font(.system(.title3, design: .rounded, weight: .bold))
    }

    /// PID説明を4項目のシートとして表示します。
    ///
    /// 責務: 1件のPIDサンプルを概要と確認観点を含む説明シートへ変換します。
    /// - Parameter sample: 説明するPIDサンプル。
    /// - Returns: 閉じる操作を持つ説明画面。
    private func helpSheet(_ sample: OBDPIDSample) -> some View {
        NavigationStack {
            List {
                Section("telemetry.help.summary") { Text(LocalizedStringKey(sample.summaryKey)) }
                Section("telemetry.help.high") { Text(LocalizedStringKey(sample.highValueKey)) }
                Section("telemetry.help.low") { Text(LocalizedStringKey(sample.lowValueKey)) }
                Section("telemetry.help.correlation") { Text(LocalizedStringKey(sample.correlationKey)) }
            }
            .navigationTitle(LocalizedStringKey(sample.nameKey))
            .toolbar { Button("common.close") { helpSample = nil } }
        }
    }

    /// 回転数と車速を優先し、不在時は先頭値で空きを補います。
    private var primarySamples: [OBDPIDSample] {
        let requests = [OBDPIDRequest(service: 0x01, pid: 0x0C), OBDPIDRequest(service: 0x01, pid: 0x0D)]
        let preferred = requests.compactMap { request in state.samples.first { $0.request == request } }
        return Array((preferred + state.samples.filter { !preferred.contains($0) }).prefix(2))
    }

    /// 車両型式が明示された拡張PIDだけを返します。
    private var vehicleSpecificSamples: [OBDPIDSample] { state.samples.filter { $0.vehicleModelCode?.isEmpty == false } }

    /// 応答済みサンプルを持つ分類を表示順で返します。
    private var availableCategories: [OBDPIDCategory] { OBDPIDCategory.allCases.filter { !samples(in: $0).isEmpty } }

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
    private func representative(in samples: [OBDPIDSample], category: OBDPIDCategory) -> OBDPIDSample? {
        samples.first(where: { $0.request == category.representativeRequest }) ?? samples.first
    }

    /// 主要PIDに対応するシンボルを返します。
    ///
    /// 責務: 1件の主要PID要求を意味の近いSF Symbolへ変換します。
    /// - Parameter request: シンボルを選ぶPID要求。
    /// - Returns: 回転数、車速、その他を区別するSF Symbol名。
    private func primarySymbol(for request: OBDPIDRequest) -> String {
        if request == OBDPIDRequest(service: 0x01, pid: 0x0C) { return "gauge.with.dots.needle.67percent" }
        if request == OBDPIDRequest(service: 0x01, pid: 0x0D) { return "road.lanes" }
        return "waveform.path.ecg"
    }

    /// 分類に対応するシンボルを返します。
    ///
    /// 責務: 1件のPID分類を分類カード用SF Symbolへ変換します。
    /// - Parameter category: シンボルを選ぶPID分類。
    /// - Returns: 分類の意味を補助するSF Symbol名。
    private func categorySymbol(_ category: OBDPIDCategory) -> String {
        switch category {
        case .engine: "engine.combustion"
        case .temperature: "thermometer.medium"
        case .fuelAndAir: "wind"
        case .driving: "steeringwheel"
        case .diagnostics: "stethoscope"
        }
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
