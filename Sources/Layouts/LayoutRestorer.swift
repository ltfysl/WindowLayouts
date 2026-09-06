import AppKit
import Foundation

/// Immutable display geometry snapshot passed into detached work so nothing
/// touches NSScreen off the main thread.
struct ScreenInfo: Equatable {
    let frame: CGRect
    let visible: CGRect
}

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

        let groups = Dictionary(grouping: layout.windows, by: \.bundleID)
        let appOrder = layout.windows.map(\.bundleID).removingDuplicates()

        // Phase 1 — launch missing apps (suspends the main actor, never blocks).
        var runningApps: [String: NSRunningApplication] = [:]
        for bundleID in appOrder {
            if let existing = Self.runningApp(for: bundleID) {
                runningApps[bundleID] = existing
                continue
            }
            statusText = "Launching \(Self.displayName(for: bundleID, in: groups))…"
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            runningApps[bundleID] = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }

        // Snapshot display geometry on main; detached work uses these values.
        let screens: [ScreenInfo] = ScreenLayout.sortedByX.map {
            ScreenInfo(frame: $0.frame, visible: $0.visibleFrame)
        }

        statusText = "Waiting for windows…"
        try? await Task.sleep(for: .milliseconds(400))

        // Phase 2 — wait for each app's windows in parallel (AX off-main).
        let windowsByApp: [String: [AXUIElement]] = await withTaskGroup(
            of: (String, [AXUIElement]).self,
            returning: [String: [AXUIElement]].self
        ) { group in
            for bundleID in appOrder {
                guard let app = runningApps[bundleID],
                      let wanted = groups[bundleID] else { continue }
                group.addTask(priority: .userInitiated) {
                    (bundleID, Self.waitForWindows(of: app, atLeast: min(wanted.count, 12)))
                }
            }
            var result: [String: [AXUIElement]] = [:]
            for await (bundleID, elements) in group {
                result[bundleID] = elements
            }
            return result
        }

        // Phase 3 — apply frames sequentially off-main (AX ordering).
        statusText = "Arranging windows…"
        let restored = await Task.detached(priority: .userInitiated) {
            Self.applyFrames(
                layout: layout,
                groups: groups,
                appOrder: appOrder,
                runningApps: runningApps,
                windowsByApp: windowsByApp,
                screens: screens
            )
        }.value

        if let first = appOrder.first, let app = runningApps[first] {
            app.activate()
        }

        statusText = "Restored \(restored) of \(layout.windows.count) windows"
        try? await Task.sleep(for: .seconds(2))
    }

    // MARK: - Static helpers (run detached; AX + pure value types only)

    private nonisolated static func waitForWindows(of app: NSRunningApplication, atLeast count: Int) -> [AXUIElement] {
        let deadline = Date().addingTimeInterval(6)
        var elements = AXBridge.windows(of: app)
        while elements.count < count && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.15)
            elements = AXBridge.windows(of: app)
        }
        return elements
    }

    private nonisolated static func applyFrames(
        layout: SavedLayout,
        groups: [String: [WindowSnapshot]],
        appOrder: [String],
        runningApps: [String: NSRunningApplication],
        windowsByApp: [String: [AXUIElement]],
        screens: [ScreenInfo]
    ) -> Int {
        var restored = 0
        for bundleID in appOrder {
            guard let app = runningApps[bundleID],
                  let wanted = groups[bundleID]?.sorted(by: { $0.slot < $1.slot }),
                  let elements = windowsByApp[bundleID] else { continue }
            let ordered = elements.reversed().filter { !AXBridge.isMinimized($0) }

            for (index, snapshot) in wanted.enumerated() {
                let target: AXUIElement?
                if snapshot.title.nonEmpty,
                   let titleMatch = ordered.first(where: { AXBridge.title(of: $0) == snapshot.title }) {
                    target = titleMatch
                } else if index < ordered.count {
                    target = ordered[index]
                } else {
                    target = nil
                }
                guard let element = target else { continue }
                if AXBridge.setFrame(element, targetFrame(for: snapshot, layoutDisplays: layout.displays, screens: screens)) {
                    restored += 1
                    AXBridge.raise(element)
                }
            }
        }
        return restored
    }

    /// Per-slot decision: same display geometry as at capture time → pixel
    /// exact; otherwise scale the stored relative frame into the current
    /// display's visible area (monitor removed/replaced/rearranged).
    private nonisolated static func targetFrame(
        for snapshot: WindowSnapshot,
        layoutDisplays: [DisplaySnapshot],
        screens: [ScreenInfo]
    ) -> CGRect {
        guard snapshot.displaySlot < layoutDisplays.count,
              snapshot.displaySlot < screens.count else {
            // Legacy layout without display info: old clamped-absolute path.
            let screen = screens.first { $0.frame.intersects(snapshot.frame) }
            return fit(snapshot.frame, into: screen?.visible)
        }
        let slot = snapshot.displaySlot
        let capturedDisplay = layoutDisplays[slot].frame
        let current = screens[slot]

        let sameGeometry =
            abs(capturedDisplay.minX - current.frame.minX) < 1 &&
            abs(capturedDisplay.width - current.frame.width) < 1 &&
            abs(capturedDisplay.height - current.frame.height) < 1

        if sameGeometry {
            return fit(snapshot.frame, into: current.visible)
        }
        let scaled = ScreenLayout.absolute(
            relX: snapshot.relX, relY: snapshot.relY,
            relW: snapshot.relW, relH: snapshot.relH,
            in: current.visible
        )
        return fit(scaled, into: current.visible)
    }

    private nonisolated static func fit(_ frame: CGRect, into visible: CGRect?) -> CGRect {
        guard let visible, visible.width > 0, visible.height > 0 else { return frame }
        var fitted = frame
        fitted.size.width = min(fitted.width, visible.width)
        fitted.size.height = min(fitted.height, visible.height)
        fitted.origin.x = min(max(fitted.minX, visible.minX), visible.maxX - fitted.width)
        fitted.origin.y = min(max(fitted.minY, visible.minY), visible.maxY - fitted.height)
        return fitted
    }

    private nonisolated static func runningApp(for bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleID && $0.activationPolicy == .regular
        }
    }

    private nonisolated static func displayName(for bundleID: String, in groups: [String: [WindowSnapshot]]) -> String {
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
