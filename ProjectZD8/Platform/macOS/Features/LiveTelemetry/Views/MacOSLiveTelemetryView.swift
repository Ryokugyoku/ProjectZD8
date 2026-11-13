#if os(macOS)
import SwiftUI

/// macOS向けに主要値、BRZ専用値、分類詳細の順でリアルタイムPIDを描画します。
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

    /// デスクトップ向けの優先度付きコックピット表示を提供します。
    ///
    /// 責務: LiveTelemetry状態を主要値が最初に読めるmacOS専用画面へ変換します。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20 * metrics.scale) {
                hero
                operationalState
                if !state.samples.isEmpty {
                    primaryDashboard
                    if !vehicleSpecificSamples.isEmpty { brzSection }
                    categoryWorkspace
                } else if state.phase == .idle {
                    waitingState
                }
                if state.phase == .failed { retryButton }
            }
            .padding(26 * metrics.scale)
            .frame(maxWidth: 1_260 * metrics.scale)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(telemetryBackground)
        .accessibilityIdentifier("macos-live-telemetry")
        .onChange(of: availableCategories) { _, categories in
            if !categories.contains(selectedCategory), let first = categories.first { selectedCategory = first }
        }
        .onAppear {
            if !availableCategories.contains(selectedCategory), let first = availableCategories.first { selectedCategory = first }
        }
    }

    /// 画面全体へ接続履歴と共通する抑制された奥行きを与える背景です。
    private var telemetryBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Color.cyan.opacity(0.1), .clear], center: .topTrailing, startRadius: 0, endRadius: 650 * metrics.scale)
        }
    }

    /// 画面の目的、応答数、BRZ値の有無を示す上部カードです。
    private var hero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20 * metrics.scale) {
                heroIdentity
                Spacer(minLength: 12 * metrics.scale)
                heroSummary
            }
            VStack(alignment: .leading, spacing: 16 * metrics.scale) {
                heroIdentity
                heroSummary
            }
        }
        .padding(24 * metrics.scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26 * metrics.scale, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }

    /// 上部カードのアイコンと説明を表示します。
    private var heroIdentity: some View {
        HStack(spacing: 18 * metrics.scale) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 31 * metrics.scale, weight: .semibold)).foregroundStyle(.cyan)
                .frame(width: 74 * metrics.scale, height: 74 * metrics.scale)
                .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous))
            VStack(alignment: .leading, spacing: 5 * metrics.scale) {
                Text("telemetry.eyebrow").font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded)).tracking(1.8 * metrics.scale).foregroundStyle(.cyan)
                Text("telemetry.title").font(.system(size: 30 * metrics.scale, weight: .bold, design: .rounded))
                Text("telemetry.subtitle").font(.system(size: 13 * metrics.scale, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }

    /// 上部カードへ応答済みPID数とBRZ拡張状態を表示します。
    private var heroSummary: some View {
        HStack(spacing: 12 * metrics.scale) {
            VStack(alignment: .trailing, spacing: 3 * metrics.scale) {
                Text(state.supportedPIDCount, format: .number)
                    .font(.system(size: 27 * metrics.scale, weight: .bold, design: .rounded).monospacedDigit())
                Text("telemetry.status.responding_count").font(.system(size: 10 * metrics.scale, weight: .semibold)).foregroundStyle(.secondary)
            }
            if let modelCode = vehicleSpecificSamples.first?.vehicleModelCode {
                Divider().frame(height: 40 * metrics.scale)
                VehicleModelBadge(modelCode: modelCode)
            }
        }
    }

    /// 通信中、探索中、停止中、失敗の現在状態を表示します。
    @ViewBuilder private var operationalState: some View {
        switch state.phase {
        case .reading:
            statusBanner("telemetry.status.reading", symbol: "dot.radiowaves.left.and.right", color: .cyan, showsProgress: true)
        case .stopping:
            statusBanner("telemetry.status.stopping", symbol: "stop.circle", color: .orange, showsProgress: true)
        case .loaded:
            statusBanner("telemetry.status.polling", symbol: "waveform.path.ecg", color: .green, showsProgress: false)
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
        HStack(spacing: 12 * metrics.scale) {
            if showsProgress { ProgressView().controlSize(.small).tint(color) } else { Image(systemName: symbol).foregroundStyle(color) }
            Text(LocalizedStringKey(key)).font(.system(size: 12 * metrics.scale, weight: .semibold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16 * metrics.scale).frame(minHeight: 46 * metrics.scale)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 15 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15 * metrics.scale, style: .continuous).stroke(color.opacity(0.18)) }
    }

    /// 回転数と車速を最優先に大きく表示します。
    private var primaryDashboard: some View {
        VStack(alignment: .leading, spacing: 12 * metrics.scale) {
            sectionHeader("telemetry.section.now", symbol: "speedometer")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300 * metrics.scale), spacing: 16 * metrics.scale)], spacing: 16 * metrics.scale) {
                ForEach(primarySamples) { sample in primaryCard(sample) }
            }
        }
    }

    /// 主要PIDを瞬時に読める大型数値カードとして描画します。
    ///
    /// 責務: 1件の主要PIDを名称、現在値、単位、観測状態を持つカードへ変換します。
    /// - Parameter sample: 表示する主要PIDサンプル。
    /// - Returns: macOS用の主要値カード。
    private func primaryCard(_ sample: OBDPIDSample) -> some View {
        HStack(spacing: 18 * metrics.scale) {
            Image(systemName: primarySymbol(for: sample.request))
                .font(.system(size: 27 * metrics.scale, weight: .semibold)).foregroundStyle(.cyan)
                .frame(width: 58 * metrics.scale, height: 58 * metrics.scale)
                .background(Color.cyan.opacity(0.13), in: RoundedRectangle(cornerRadius: 18 * metrics.scale, style: .continuous))
            VStack(alignment: .leading, spacing: 5 * metrics.scale) {
                Text(LocalizedStringKey(sample.nameKey)).font(.system(size: 12 * metrics.scale, weight: .semibold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 7 * metrics.scale) {
                    Text(sample.value, format: .number.precision(.fractionLength(0...1)))
                        .font(.system(size: 40 * metrics.scale, weight: .bold, design: .rounded).monospacedDigit())
                    Text(sample.unit).font(.system(size: 11 * metrics.scale, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                }
            }
            Spacer(minLength: 8 * metrics.scale)
            Button { helpSample = sample } label: { Image(systemName: "info.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .popover(isPresented: helpBinding(for: sample)) { helpPopover(sample) }
                .accessibilityLabel("telemetry.help.open")
        }
        .padding(20 * metrics.scale).frame(maxWidth: .infinity, minHeight: 126 * metrics.scale, alignment: .leading)
        .background(LinearGradient(colors: [Color.cyan.opacity(0.13), Color.primary.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous).stroke(Color.cyan.opacity(0.2)) }
    }

    /// BRZ車種専用PIDを標準値から区別して表示します。
    private var brzSection: some View {
        VStack(alignment: .leading, spacing: 14 * metrics.scale) {
            HStack {
                sectionHeader("telemetry.section.brz", symbol: "car.side.fill")
                Spacer()
                if let modelCode = vehicleSpecificSamples.first?.vehicleModelCode { VehicleModelBadge(modelCode: modelCode) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 205 * metrics.scale), spacing: 12 * metrics.scale)], spacing: 12 * metrics.scale) {
                ForEach(vehicleSpecificSamples) { sample in sampleCard(sample, tint: .cyan) }
            }
        }
        .padding(19 * metrics.scale)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 23 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 23 * metrics.scale, style: .continuous).stroke(Color.cyan.opacity(0.22)) }
    }

    /// 分類選択と選択分類の全現在値を一体で表示します。
    private var categoryWorkspace: some View {
        VStack(alignment: .leading, spacing: 14 * metrics.scale) {
            sectionHeader("telemetry.section.all", symbol: "square.grid.2x2")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8 * metrics.scale) {
                    ForEach(availableCategories, id: \.self) { category in categoryButton(category) }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210 * metrics.scale), spacing: 12 * metrics.scale)], spacing: 12 * metrics.scale) {
                ForEach(samples(in: selectedCategory)) { sample in sampleCard(sample, tint: sample.vehicleModelCode == nil ? .accentColor : .cyan) }
            }
        }
    }

    /// 1分類を選択状態付きの操作へ変換します。
    ///
    /// 責務: 1件のPID分類を代表値付き分類選択ボタンへ変換します。
    /// - Parameter category: 表示するPID分類。
    /// - Returns: 分類詳細を切り替えるボタン。
    private func categoryButton(_ category: OBDPIDCategory) -> some View {
        let values = samples(in: category)
        let isSelected = selectedCategory == category
        return Button { selectedCategory = category } label: {
            HStack(spacing: 9 * metrics.scale) {
                Image(systemName: categorySymbol(category))
                Text(LocalizedStringKey(category.nameKey)).fontWeight(.semibold)
                if let sample = representative(in: values, category: category) {
                    Text(formatted(sample)).font(.system(.caption, design: .monospaced).weight(.bold)).opacity(0.8)
                }
            }
            .font(.system(size: 11 * metrics.scale, design: .rounded))
            .padding(.horizontal, 14 * metrics.scale).frame(minHeight: 44 * metrics.scale)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045), in: Capsule())
            .overlay { Capsule().stroke(isSelected ? Color.accentColor.opacity(0.38) : Color.primary.opacity(0.07)) }
        }
        .buttonStyle(.plain).accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 補助PIDを情報操作付きの小型カードとして描画します。
    ///
    /// 責務: 1件のPIDサンプルを名称と単位付き現在値を持つ補助カードへ変換します。
    /// - Parameters:
    ///   - sample: 表示するPIDサンプル。
    ///   - tint: 値の識別へ使用する色。
    /// - Returns: PID説明を開ける小型カード。
    private func sampleCard(_ sample: OBDPIDSample, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10 * metrics.scale) {
            HStack {
                Text(LocalizedStringKey(sample.nameKey)).font(.system(size: 11 * metrics.scale, weight: .semibold)).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 4 * metrics.scale)
                Button { helpSample = sample } label: { Image(systemName: "info.circle") }.buttonStyle(.plain)
                    .popover(isPresented: helpBinding(for: sample)) { helpPopover(sample) }
                    .accessibilityLabel("telemetry.help.open")
            }
            HStack(alignment: .firstTextBaseline, spacing: 6 * metrics.scale) {
                Text(sample.value, format: .number.precision(.fractionLength(0...2)))
                    .font(.system(size: 25 * metrics.scale, weight: .bold, design: .rounded).monospacedDigit())
                Text(sample.unit).font(.system(size: 10 * metrics.scale, weight: .semibold, design: .monospaced)).foregroundStyle(tint)
            }
        }
        .padding(16 * metrics.scale).frame(maxWidth: .infinity, minHeight: 96 * metrics.scale, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 17 * metrics.scale, style: .continuous).stroke(Color.primary.opacity(0.07)) }
    }

    /// 未接続時の次の操作を表示します。
    private var waitingState: some View {
        ContentUnavailableView("telemetry.status.waiting_for_connection", systemImage: "cable.connector")
            .padding(38 * metrics.scale).frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24 * metrics.scale, style: .continuous))
    }

    /// 失敗後の再取得操作です。
    private var retryButton: some View {
        Button { send(.retryRequested) } label: { Label("telemetry.retry", systemImage: "arrow.clockwise") }
            .buttonStyle(.borderedProminent).controlSize(.large)
    }

    /// ローカライズ済みセクション見出しを生成します。
    ///
    /// 責務: 1件の見出しキーとシンボルを同じ視覚階層へ変換します。
    /// - Parameters:
    ///   - key: 見出しのローカライズキー。
    ///   - symbol: 見出しを補助するSF Symbol名。
    /// - Returns: セクション見出し。
    private func sectionHeader(_ key: String, symbol: String) -> some View {
        Label(LocalizedStringKey(key), systemImage: symbol)
            .font(.system(size: 18 * metrics.scale, weight: .bold, design: .rounded))
    }

    /// 指定PIDだけに対応するPopover表示Bindingを返します。
    ///
    /// 責務: 現在の説明対象を1件のPIDカード用表示Bindingへ射影します。
    /// - Parameter sample: 表示状態を関連付けるPIDサンプル。
    /// - Returns: 指定PIDが説明対象のときだけ有効なBinding。
    private func helpBinding(for sample: OBDPIDSample) -> Binding<Bool> {
        Binding(get: { helpSample?.id == sample.id }, set: { if !$0 { helpSample = nil } })
    }

    /// PID説明を4項目のPopoverとして表示します。
    ///
    /// 責務: 1件のPIDサンプルを概要と確認観点を含む説明Popoverへ変換します。
    /// - Parameter sample: 説明するPIDサンプル。
    /// - Returns: PID説明Popover。
    private func helpPopover(_ sample: OBDPIDSample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(sample.nameKey)).font(.headline)
            helpRow("telemetry.help.summary", valueKey: sample.summaryKey)
            helpRow("telemetry.help.high", valueKey: sample.highValueKey)
            helpRow("telemetry.help.low", valueKey: sample.lowValueKey)
            helpRow("telemetry.help.correlation", valueKey: sample.correlationKey)
        }.padding(18).frame(width: 360)
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
    /// 責務: 1件のPID分類を分類選択用SF Symbolへ変換します。
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
