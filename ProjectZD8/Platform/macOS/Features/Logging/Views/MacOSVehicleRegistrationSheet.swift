#if os(macOS)
import SwiftUI

/// 未登録の車両に名前を付けて登録するシート(`awaitingVehicleRegistration` フェーズで表示)。
struct MacOSVehicleRegistrationSheet: View {
    let identification: VehicleIdentification
    let send: (DriveSessionAction) -> Void

    @State private var name = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.lg) {
            Text("drive.register.title").font(InsightTypography.screenTitle)
            Text("drive.register.message").font(InsightTypography.body).foregroundStyle(.secondary)

            InsightCard {
                VStack(spacing: InsightSpacing.sm) {
                    KeyValueRow(Text("drive.register.vin"), value: Text(verbatim: identification.vin ?? "—"), isNumeric: true)
                    KeyValueRow(Text("drive.register.adapter"), value: Text(verbatim: identification.adapterDescription))
                    KeyValueRow(Text("drive.register.protocol"), value: Text(verbatim: identification.protocolDescription))
                }
            }

            TextField("drive.register.name", text: $name, prompt: Text("drive.register.name.prompt"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Spacer()
                Button(role: .cancel) {
                    send(.registrationCancelled)
                } label: {
                    Text("common.cancel")
                }
                .keyboardShortcut(.cancelAction)
                Button(action: submit) { Text("drive.register.submit") }
                    .buttonStyle(.insightPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(InsightSpacing.xl)
        .frame(width: MacOSAppShellMetrics.sheetWidth)
        .interactiveDismissDisabled()
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        send(.registrationSubmitted(name: trimmedName))
    }
}
#endif
