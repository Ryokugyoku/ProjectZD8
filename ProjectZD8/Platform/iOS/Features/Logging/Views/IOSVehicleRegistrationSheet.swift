#if os(iOS)
import SwiftUI

/// 未登録の車両に名前を付けて登録するシートです。VINとアダプター・プロトコルの情報を示します。
struct IOSVehicleRegistrationSheet: View {
    let identification: VehicleIdentification
    let adapter: AdapterDescriptor?
    let send: (DriveSessionAction) -> Void

    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("drive.registration.name", text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                        .onSubmit(register)
                } header: {
                    Text("drive.registration.nameHeader")
                } footer: {
                    Text("drive.registration.footer")
                }
                Section {
                    LabeledContent("drive.registration.vin") {
                        if let vin = identification.vin, !vin.isEmpty {
                            Text(verbatim: vin).font(.body.monospaced()).textSelection(.enabled)
                        } else {
                            Text("common.unavailable").foregroundStyle(.secondary)
                        }
                    }
                    if let adapter {
                        LabeledContent("drive.registration.adapter") { Text(verbatim: adapter.displayName) }
                    }
                    LabeledContent("drive.registration.adapterInfo") { Text(verbatim: identification.adapterDescription) }
                    LabeledContent("drive.registration.protocol") { Text(verbatim: identification.protocolDescription) }
                } header: {
                    Text("drive.registration.detected")
                }
            }
            .navigationTitle(Text("drive.registration.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { send(.registrationCancelled) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("drive.registration.submit", action: register)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
        .interactiveDismissDisabled()
        .presentationDetents([.large])
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 責務: 入力された名前で登録を送ります。
    private func register() {
        guard !trimmedName.isEmpty else { return }
        send(.registrationSubmitted(name: trimmedName))
    }
}
#endif
