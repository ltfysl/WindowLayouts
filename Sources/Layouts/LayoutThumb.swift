import AppKit
import SwiftUI

/// Mini schematic of a saved layout: display outlines + one colored rect per
/// window, positioned via the stored relative frames.
struct LayoutThumb: View {
    let layout: SavedLayout

    private static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .yellow]
    private static var colorCache: [String: Color] = [:]

    static func appColor(_ name: String) -> Color {
        if let cached = colorCache[name] { return cached }
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let index = (hash % palette.count + palette.count) % palette.count
        let color = palette[index]
        colorCache[name] = color
        return color
    }

    var body: some View {
        GeometryReader { proxy in
            let bounds = Self.unionBounds(layout)
            ZStack(alignment: .topLeading) {
                if layout.displays.isEmpty {
                    // Legacy layout without display info: draw windows by
                    // absolute frames scaled into the thumb.
                    ForEach(Array(layout.windows.enumerated()), id: \.element.id) { _, window in
                        windowRect(
                            color: Self.appColor(window.appName),
                            frame: window.frame,
                            container: bounds,
                            in: proxy.size,
                            bounds: bounds
                        )
                    }
                } else {
                    ForEach(Array(layout.displays.enumerated()), id: \.offset) { _, display in
                        outline(display.frame, container: bounds, in: proxy.size)
                    }
                    ForEach(layout.windows) { window in
                        let container = displayFrame(for: window)
                        windowRect(
                            color: Self.appColor(window.appName),
                            frame: ScreenLayout.absolute(
                                relX: window.relX, relY: window.relY,
                                relW: window.relW, relH: window.relH,
                                in: container
                            ),
                            container: bounds,
                            in: proxy.size,
                            bounds: bounds
                        )
                    }
                }
            }
        }
        .frame(width: 76, height: 44)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
        .clipped()
    }

    private func displayFrame(for window: WindowSnapshot) -> CGRect {
        let displays = layout.displays
        guard !displays.isEmpty else { return .zero }
        let slot = min(max(window.displaySlot, 0), displays.count - 1)
        return displays[slot].frame
    }

    private func outline(_ frame: CGRect, container: CGRect, in size: CGSize) -> some View {
        let rect = normalize(frame, container: container, size: size)
        return RoundedRectangle(cornerRadius: 1.5)
            .strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.5)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    private func windowRect(color: Color, frame: CGRect, container: CGRect, in size: CGSize, bounds: CGRect) -> some View {
        let rect = normalize(frame, container: container, size: size)
        return RoundedRectangle(cornerRadius: 1)
            .fill(color.opacity(0.85))
            .frame(width: max(rect.width, 2), height: max(rect.height, 2))
            .offset(x: rect.minX, y: rect.minY)
    }

    private func normalize(_ frame: CGRect, container: CGRect, size: CGSize) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let x = (frame.minX - container.minX) / bounds.width * size.width
        let y = (frame.minY - container.minY) / bounds.height * size.height
        let w = frame.width / bounds.width * size.width
        let h = frame.height / bounds.height * size.height
        return CGRect(x: max(0, x), y: max(0, y), width: min(w, size.width), height: min(h, size.height))
    }

    private var bounds: CGRect {
        Self.unionBounds(layout)
    }

    static func unionBounds(_ layout: SavedLayout) -> CGRect {
        if !layout.displays.isEmpty {
            var union = layout.displays[0].frame
            for display in layout.displays.dropFirst() {
                union = union.union(display.frame)
            }
            return union
        }
        guard let first = layout.windows.first else {
            return CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        var union = first.frame
        for window in layout.windows.dropFirst() {
            union = union.union(window.frame)
        }
        return union
    }
}
