#if os(iOS)
import SwiftUI

/// iOSの交通規制データの管理画面(シート)の画面ルートです。
///
/// 「更新を確認」・47都道府県の行・出典と注意書きを並べ、削除の確認とエラーの alert をつなぎます。
/// 判定と遷移は `RoadRegulationSettingsState` とその純粋型が持ち、この型は部品の配置と Action の送出だけを行います。
struct IOSRoadRegulationDataView: View {
    /// シートを閉じるシステムの操作です。
    @Environment(\.dismiss) private var dismiss
    /// 値を差し込む文言に使うロケールです。
    @Environment(\.locale) private var locale

    /// 管理画面の状態です。
    let state: RoadRegulationSettingsState
    /// 管理画面の操作を通知するクロージャです。
    let send: (RoadRegulationSettingsAction) -> Void

    /// 一覧と alert を持つ管理画面を提供します。
    ///
    /// 責務: 画面を開いた時に `appeared` を送り、削除は確認の alert を経てから Action を送ります。
    var body: some View {
        NavigationStack {
            List {
                Section {
                    IOSRoadRegulationDataCatalogHeader(content: RoadRegulationCatalogHeaderContent(status: state.catalogStatus)) {
                        send(.checkUpdatesRequested)
                    }
                }
                Section {
                    ForEach(state.rows) { row in
                        prefectureRow(RoadRegulationPrefectureRowContent(row: row))
                    }
                }
                Section {
                    IOSRoadRegulationDataAttributionSection(attribution: state.attribution, usedOnText: formatter.usedOnText(state.attribution))
                }
            }
            .navigationTitle("road_regulation.data.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("common.close") { dismiss() }
                    .accessibilityIdentifier("ios-road-regulation-close")
            }
        }
        .onAppear { send(.appeared) }
        .alert("road_regulation.data.remove_confirm.title", isPresented: removalBinding) {
            Button("road_regulation.data.remove_confirm.confirm", role: .destructive) { send(.removeConfirmed) }
            Button("road_regulation.data.remove_confirm.cancel", role: .cancel) { send(.removeCancelled) }
        } message: {
            Text("road_regulation.data.remove_confirm.message")
        }
        .alert("road_regulation.error.title", isPresented: errorBinding) {
            Button("common.close", role: .cancel) { send(.errorDismissed) }
        } message: {
            if let error = state.presentedError {
                Text(LocalizedStringKey(RoadRegulationSettingsTextKeys().errorKey(for: error)))
            }
        }
        .accessibilityIdentifier("ios-road-regulation-data-screen")
    }

    /// 値を差し込む文言を作る型です(画面のロケールに合わせます)。
    private var formatter: RoadRegulationSettingsTextFormatter {
        RoadRegulationSettingsTextFormatter(locale: locale)
    }

    /// 削除の確認を出すかの束縛です。閉じる操作はボタンが Action として送ります。
    private var removalBinding: Binding<Bool> {
        Binding(get: { state.pendingRemoval != nil }, set: { _ in })
    }

    /// エラーを出すかの束縛です。閉じる操作はボタンが Action として送ります。
    private var errorBinding: Binding<Bool> {
        Binding(get: { state.presentedError != nil }, set: { _ in })
    }

    /// 都道府県の1行を作ります。
    ///
    /// 責務: 行の操作を、その県の Action の送出へつなぎます。
    /// - Parameter content: 行に出す内容。
    /// - Returns: 都道府県の1行。
    private func prefectureRow(_ content: RoadRegulationPrefectureRowContent) -> some View {
        IOSRoadRegulationDataPrefectureRow(
            content: content,
            formatter: formatter,
            download: { send(.downloadRequested(content.prefecture)) },
            remove: { send(.removeRequested(content.prefecture)) },
            cancel: { send(.cancelRequested) }
        )
    }
}
#endif
