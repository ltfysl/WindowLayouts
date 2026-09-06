import SwiftUI

// Design tokens — locked before markup (ui-craft §4).
// Native-first power-user utility: system materials, one cobalt accent,
// radius 6/8, hover = 6% ink overlay. Density 6, motion 2.
enum Tokens {
    static let accent = Color(red: 0.29, green: 0.51, blue: 0.95) // cobalt #4A82F2
    static let rowCornerRadius: CGFloat = 8
    static let controlCornerRadius: CGFloat = 6
}

@MainActor
enum AppServices {
    static let store = LayoutStore()
    static let restorer = LayoutRestorer()
    static let hotKeys = HotKeyManager()
}

@main
struct LayoutsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            LayoutsListView(store: AppServices.store, restorer: AppServices.restorer)
                .tint(Tokens.accent)
        } label: {
            Label("Layouts", systemImage: "rectangle.split.2x2")
        }
        .menuBarExtraStyle(.window)

        Settings {
            LayoutsSettingsView()
                .tint(Tokens.accent)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppServices.hotKeys.onDigit = { digit in
            Task { @MainActor in
                let enabled = UserDefaults.standard.object(forKey: "hotkeysEnabled") as? Bool ?? true
                guard enabled else { return }
                let layouts = AppServices.store.layouts
                guard layouts.indices.contains(digit - 1) else { return }
                await AppServices.restorer.restore(layouts[digit - 1])
            }
        }
        AppServices.hotKeys.install()
    }
}
