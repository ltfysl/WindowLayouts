import AppKit
import Foundation

/// Display geometry helpers: stable slot order (sorted by X), relative/absolute
/// frame math, and capture-time display snapshots.
enum ScreenLayout {
    static var sortedByX: [NSScreen] {
        NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
    }

    static func snapshots() -> [DisplaySnapshot] {
        sortedByX.map { screen in
            let frame = screen.frame
            return DisplaySnapshot(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        }
    }

    static func screen(atSlot slot: Int) -> NSScreen? {
        let screens = sortedByX
        guard !screens.isEmpty else { return nil }
        return screens[min(max(slot, 0), screens.count - 1)]
    }

    static func visibleFrame(atSlot slot: Int) -> CGRect {
        screen(atSlot: slot)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    static func slot(for frame: CGRect) -> Int {
        for (index, screen) in sortedByX.enumerated() where screen.frame.intersects(frame) {
            return index
        }
        // Fallback: nearest display by center distance.
        let center = CGPoint(x: frame.midX, y: frame.midY)
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, screen) in sortedByX.enumerated() {
            let screenCenter = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            let dx = Double(center.x - screenCenter.x)
            let dy = Double(center.y - screenCenter.y)
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    static func relative(_ window: CGRect, in container: CGRect) -> (relX: Double, relY: Double, relW: Double, relH: Double) {
        guard container.width > 0, container.height > 0 else { return (0, 0, 1, 1) }
        return (
            Double((window.minX - container.minX) / container.width),
            Double((window.minY - container.minY) / container.height),
            Double(window.width / container.width),
            Double(window.height / container.height)
        )
    }

    static func absolute(relX: Double, relY: Double, relW: Double, relH: Double, in container: CGRect) -> CGRect {
        CGRect(
            x: container.minX + relX * container.width,
            y: container.minY + relY * container.height,
            width: relW * container.width,
            height: relH * container.height
        )
    }
}
