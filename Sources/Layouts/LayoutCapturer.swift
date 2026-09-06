import AppKit
import Foundation

/// Captures the current window arrangement via the Accessibility API.
/// Heavy AX reads run detached and parallel per app — the main thread only
/// collects the app metadata (NSWorkspace is main-thread) and the results.
enum LayoutCapturer {
    struct AppInfo {
        let pid: pid_t
        let bundleID: String
        let name: String
    }

    /// Metadata pass on the main thread, then parallel AX reads off it.
    static func appInfos() -> [AppInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && !$0.isTerminated
                    && $0.bundleIdentifier != nil
                    && $0.processIdentifier != ownPID
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            .map { AppInfo(pid: pid_t($0.processIdentifier), bundleID: $0.bundleIdentifier ?? "", name: $0.localizedName ?? "Unknown") }
    }

    static func captureCurrentWindows(appInfos: [AppInfo]) async -> [WindowSnapshot] {
        let collected = await withTaskGroup(of: [WindowSnapshot].self) { group in
            for app in appInfos {
                group.addTask(priority: .userInitiated) {
                    var slot = 0
                    var snapshots: [WindowSnapshot] = []
                    for window in AXBridge.windows(ofPID: app.pid) {
                        guard !AXBridge.isMinimized(window),
                              let frame = AXBridge.frame(of: window),
                              frame.width >= 80, frame.height >= 80 else { continue }
                        snapshots.append(WindowSnapshot.make(
                            bundleID: app.bundleID,
                            appName: app.name,
                            title: AXBridge.title(of: window),
                            frame: frame,
                            slot: slot
                        ))
                        slot += 1
                    }
                    return snapshots
                }
            }
            var all: [WindowSnapshot] = []
            for await part in group {
                all.append(contentsOf: part)
            }
            return all
        }
        // Deterministic order regardless of task completion order.
        return collected.sorted { ($0.appName, $0.slot) < ($1.appName, $1.slot) }
    }
}
