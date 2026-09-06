import AppKit
import Foundation

@Observable
@MainActor
final class LayoutRestorer {
    private(set) var isRestoring = false
    private(set) var statusText = ""

    func restore(_ layout: SavedLayout) async {
        guard !isRestoring, !layout.windows.isEmpty else { return }
        guard AXBridge.isTrusted else {
            AXBridge.promptForTrust()
            return
        }

        isRestoring = true
        defer {
            isRestoring = false
            statusText = ""
        }

        // Launch everything that isn't running yet, preserving capture order.
        let groups = Dictionary(grouping: layout.windows, by: \.bundleID)
        let appOrder = layout.windows.map(\.bundleID).removingDuplicates()

        var runningApps: [String: NSRunningApplication] = [:]
        for bundleID in appOrder {
            if let existing = runningApp(for: bundleID) {
                runningApps[bundleID] = existing
                continue
            }
            statusText = "Launching \(appName(for: bundleID, in: groups))…"
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            runningApps[bundleID] = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }

        statusText = "Arranging windows…"
        try? await Task.sleep(for: .milliseconds(500))

        // Per-slot decision: if the physical display at this slot still has
        // the same geometry as at capture time, restore pixel-exact; otherwise
        // (monitor removed/replaced/rearranged) fall back to the stored
        // relative frame scaled into the current display's visible area.
        let currentScreens = ScreenLayout.sortedByX

        func targetFrame(for snapshot: WindowSnapshot) -> CGRect {
            guard snapshot.displaySlot < layout.displays.count,
                  snapshot.displaySlot < currentScreens.count else {
                // Legacy layout (no display info): old clamped-absolute path.
                let screen = NSScreen.screens.first { $0.frame.intersects(snapshot.frame) } ?? NSScreen.main
                return fit(snapshot.frame, into: screen)
            }
            let slot = snapshot.displaySlot
            let capturedDisplay = layout.displays[slot].frame
            let currentScreen = currentScreens[slot]

            let sameGeometry =
                abs(capturedDisplay.minX - currentScreen.frame.minX) < 1 &&
                abs(capturedDisplay.width - currentScreen.frame.width) < 1 &&
                abs(capturedDisplay.height - currentScreen.frame.height) < 1

            if sameGeometry {
                return fit(snapshot.frame, into: currentScreen)
            }
            let scaled = ScreenLayout.absolute(
                relX: snapshot.relX, relY: snapshot.relY,
                relW: snapshot.relW, relH: snapshot.relH,
                in: currentScreen.visibleFrame
            )
            return fit(scaled, into: currentScreen)
        }

        var restored = 0
        for bundleID in appOrder {
            guard let app = runningApps[bundleID],
                  let wanted = groups[bundleID]?.sorted(by: { $0.slot < $1.slot }) else { continue }

            let elements = await waitForWindows(of: app, atLeast: min(wanted.count, 12))
            // AX reports windows bottom-up; match capture order to stacking order.
            let ordered = elements.reversed().filter { !AXBridge.isMinimized($0) }

            for (index, snapshot) in wanted.enumerated() {
                let target: AXUIElement?
                if let titleMatch = ordered.first(where: { AXBridge.title(of: $0) == snapshot.title && snapshot.title.nonEmpty }) {
                    target = titleMatch
                } else if index < ordered.count {
                    target = ordered[index]
                } else {
                    target = nil
                }
                guard let element = target else { continue }
                if AXBridge.setFrame(element, targetFrame(for: snapshot)) {
                    restored += 1
                    AXBridge.raise(element)
                }
            }
        }

        if let first = appOrder.first, let app = runningApps[first] {
            app.activate()
        }

        statusText = "Restored \(restored) of \(layout.windows.count) windows"
        try? await Task.sleep(for: .seconds(2))
    }

    private func runningApp(for bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleID && $0.activationPolicy == .regular
        }
    }

    /// Polls until the app reports the expected number of windows, giving
    /// freshly launched apps time to restore their session windows.
    private func waitForWindows(of app: NSRunningApplication, atLeast count: Int) -> [AXUIElement] {
        let deadline = Date().addingTimeInterval(6)
        var elements = AXBridge.windows(of: app)
        while elements.count < count && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            elements = AXBridge.windows(of: app)
        }
        return elements
    }

    /// Clamps a captured frame into the visible area of the target screen so
    /// layouts captured on a bigger display still land fully on-screen.
    private func fit(_ frame: CGRect, into screen: NSScreen?) -> CGRect {
        guard let visible = screen?.visibleFrame else { return frame }
        var fitted = frame
        fitted.size.width = min(fitted.width, visible.width)
        fitted.size.height = min(fitted.height, visible.height)
        fitted.origin.x = min(max(fitted.minX, visible.minX), visible.maxX - fitted.width)
        fitted.origin.y = min(max(fitted.minY, visible.minY), visible.maxY - fitted.height)
        return fitted
    }

    private func appName(for bundleID: String, in groups: [String: [WindowSnapshot]]) -> String {
        groups[bundleID]?.first?.appName ?? bundleID
    }
}

private extension String {
    var nonEmpty: Bool { !isEmpty }
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
