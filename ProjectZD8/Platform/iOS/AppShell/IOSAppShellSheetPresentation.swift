#if os(iOS)
import SwiftUI

/// iOSシェルの上に出すシート(車両を特定できなかったログの紐付けと、記録開始方法の選択)を接続する修飾子です。
///
/// 表示の要否はそれぞれのモデルの状態だけで決まり、この型は表示状態の Binding とシートの内容の接続だけを行います。
struct IOSAppShellSheetPresentation: ViewModifier {
    /// 車両を特定できなかったログの警告と紐付けを提供するモデルです。
    let vehicleUnknownSessionModel: VehicleUnknownSessionModel

    /// 紐付け先の候補にする登録車両を提供するモデルです。
    let vehicleManagementModel: VehicleManagementModel

    /// 自動記録設定と記録開始方法の選択画面の状態を提供するモデルです。
    let automaticRecordingModel: AutomaticRecordingPreferenceModel

    /// シートの内容へ適用する言語のロケール識別子です。
    let localeIdentifier: String

    /// シートを接続した表示を返します。
    ///
    /// 責務: 紐付け画面と選択画面を、それぞれの表示状態とロケールに結び付けます。
    /// - Parameter content: シートを重ねる表示。
    /// - Returns: シートを接続した表示。
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: vehicleUnknownSessionAssignmentBinding) {
                IOSVehicleUnknownSessionAssignmentView(
                    state: vehicleUnknownSessionModel.assignment,
                    vehicles: vehicleManagementModel.state.vehicles,
                    send: vehicleUnknownSessionModel.send
                )
                .environment(\.locale, Locale(identifier: localeIdentifier))
            }
            .sheet(isPresented: automaticRecordingChoicePromptBinding) {
                IOSAutomaticRecordingChoiceView { automaticRecordingModel.send(.promptChoiceSelected($0)) }
                    .environment(\.locale, Locale(identifier: localeIdentifier))
            }
    }

    /// 車両を特定できなかったログの紐付け画面の表示状態です。
    ///
    /// スワイプで閉じた時は、閉じる操作としてモデルへ通知します。
    private var vehicleUnknownSessionAssignmentBinding: Binding<Bool> {
        Binding(
            get: { vehicleUnknownSessionModel.assignment.isPresented },
            set: { isPresented in
                if !isPresented { vehicleUnknownSessionModel.send(.assignmentDismissed) }
            }
        )
    }

    /// 記録開始方法の選択画面の表示状態です。
    ///
    /// 選択せずに閉じる経路は持たないため、書き込みは無視し、表示済みになった時だけ閉じます。
    private var automaticRecordingChoicePromptBinding: Binding<Bool> {
        Binding(
            get: { automaticRecordingModel.state.isChoicePromptPresented },
            set: { _ in }
        )
    }
}
#endif
