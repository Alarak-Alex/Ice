import ServiceManagement
import SwiftUI

struct LaunchAtLoginSettingsRow: View {
    @State private var status = SMAppService.mainApp.status
    @State private var errorMessage = ""
    @State private var isPresentingError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: Binding(
                get: { status == .enabled || status == .requiresApproval },
                set: setEnabled
            ))
            if status == .requiresApproval {
                Text("Approve Ice in System Settings to enable launch at login.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open Login Items") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .buttonStyle(.link)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
        .alert("Unable to change login item", isPresented: $isPresentingError) {
            Button("Open Login Items") {
                SMAppService.openSystemSettingsLoginItems()
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
            isPresentingError = true
        }
        status = SMAppService.mainApp.status
    }
}
