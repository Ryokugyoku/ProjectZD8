import SwiftUI

/// RevTorque Insight のエントリポイントです。
@main
struct ProjectZD8App: App {
    #if os(macOS)
    @State private var launch = Launch<MacOSApplicationComposition> { try MacOSApplicationComposition() }
    #else
    @State private var launch = Launch<IOSApplicationComposition> { try IOSApplicationComposition() }
    #endif

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            switch launch.outcome {
            case .ready(let composition):
                MacOSAppShellView(
                    navigation: composition.navigation,
                    deviceConnection: composition.core.deviceConnection,
                    driveSession: composition.core.driveSession,
                    liveTelemetry: composition.core.liveTelemetry,
                    vehicles: composition.core.vehicles,
                    maintenance: composition.core.maintenance,
                    logHistory: composition.core.logHistory,
                    settings: composition.core.settings,
                    sync: composition.core.sync,
                    onAnalysisRequested: { composition.core.analysis.send(.openSession($0)) },
                    analysis: { MacOSAnalysisView(model: composition.core.analysis, content: composition.core.analysisContent) }
                )
                .task { composition.core.launch() }
            case .failed:
                MacOSLaunchFailureView(message: Text("launch.failure.message"))
            case .testHost:
                EmptyView()
            }
        }
        .commands {
            if case .ready(let composition) = launch.outcome {
                MacOSAppCommands(
                    navigation: composition.navigation,
                    deviceConnection: composition.core.deviceConnection,
                    driveSession: composition.core.driveSession,
                    vehicles: composition.core.vehicles,
                    maintenance: composition.core.maintenance,
                    logHistory: composition.core.logHistory,
                    sync: composition.core.sync
                )
            }
        }
        Settings {
            if case .ready(let composition) = launch.outcome {
                MacOSSettingsView(
                    settings: composition.core.settings,
                    deviceConnection: composition.core.deviceConnection,
                    sync: composition.core.sync
                )
            }
        }
        #else
        WindowGroup {
            switch launch.outcome {
            case .ready(let composition):
                IOSAppShellView(
                    deviceConnection: composition.core.deviceConnection,
                    driveSession: composition.core.driveSession,
                    liveTelemetry: composition.core.liveTelemetry,
                    vehicles: composition.core.vehicles,
                    maintenance: composition.core.maintenance,
                    logHistory: composition.core.logHistory,
                    settings: composition.core.settings,
                    sync: composition.core.sync,
                    analysis: { IOSAnalysisView(model: composition.core.analysis, content: composition.core.analysisContent, sessionID: $0) }
                )
                .task { composition.core.launch() }
                .onChange(of: composition.core.deviceConnection.state.defaultAdapter, initial: true) { _, adapter in
                    composition.updateArrivalMonitoring(for: adapter)
                }
            case .failed:
                IOSLaunchFailureView(message: Text("launch.failure.message"))
            case .testHost:
                EmptyView()
            }
        }
        #endif
    }
}

/// 起動時の依存組み立ての結果を1回だけ求めて保持します。
@MainActor
@Observable
final class Launch<Composition> {
    /// 起動の結果です。
    enum Outcome {
        /// 依存を組み立てられた。
        case ready(Composition)
        /// データベースなどを準備できなかった。画面で明示します。
        case failed
        /// 単体テストのホストとして起動した。ユーザーデータに触れないよう何も組み立てません。
        case testHost
    }

    let outcome: Outcome

    /// 責務: テストホストでなければ依存を組み立て、失敗を結果として保持します。
    init(make: () throws -> Composition) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            outcome = .testHost
        } else if let composition = try? make() {
            outcome = .ready(composition)
        } else {
            outcome = .failed
        }
    }
}
