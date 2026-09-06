import AppKit
import Foundation

/// Reads the current on-screen window arrangement via the Accessibility API.
enum LayoutCapturer {
    static func captureCurrentWindows() -> [WindowSnapshot] {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let apps = NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && !$0.isTerminated
                    && $0.bundleIdentifier != nil
                    && $0.processIdentifier != ownPID
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        var snapshots: [WindowSnapshot] = []
        for app in apps {
            var slot = 0
            for window in AXBridge.windows(of: app) {
                guard !AXBridge.isMinimized(window),
                      let frame = AXBridge.frame(of: window),
                      frame.width >= 80, frame.height >= 80 else { continue }
                snapshots.append(WindowSnapshot.make(
                    bundleID: app.bundleIdentifier ?? "",
                    appName: app.localizedName ?? "Unknown",
                    title: AXBridge.title(of: window),
                    frame: frame,
                    slot: slot
                ))
                slot += 1
            }
        }
        return snapshots
    }
}
