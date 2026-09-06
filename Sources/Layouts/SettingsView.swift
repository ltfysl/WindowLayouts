import SwiftUI
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}

struct LaunchAtLoginToggle: View {
    @State private var isEnabled = LaunchAtLogin.isEnabled
    @State private var showFailure = false

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { isEnabled },
            set: { newValue in
                if LaunchAtLogin.setEnabled(newValue) {
                    isEnabled = newValue
                } else {
                    showFailure = true
                }
            }
        ))
        .alert("Could not update login item", isPresented: $showFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Registering the login item failed. The app may not be running from a proper .app bundle.")
        }
    }
}

struct LayoutsSettingsView: View {
    @AppStorage("hotkeysEnabled") private var hotkeysEnabled = true

    var body: some View {
        Form {
            Section {
                LaunchAtLoginToggle()
            }
            Section("Keyboard") {
                Toggle("Restore with ⌥⌘⌃ + number", isOn: $hotkeysEnabled)
                Text("The first nine layouts map to 1…9 in menu order. The shortcut works system-wide.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Captures store app bundle IDs, window titles and frames locally in ~/Library/Application Support/Layouts. Nothing leaves your machine.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
    }
}
