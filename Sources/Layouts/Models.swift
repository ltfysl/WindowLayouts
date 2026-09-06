import AppKit
import Foundation

/// One physical display as it was arranged at capture time (sorted by X).
struct DisplaySnapshot: Codable, Equatable, Hashable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0

    var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct WindowSnapshot: Codable, Identifiable, Hashable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var title: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// Which display (sorted-by-X index) the window was on at capture time.
    var displaySlot: Int
    /// Position/size relative to that display's visible frame (0…1) — used to
    /// restore sensibly when the monitor arrangement has changed.
    var relX: Double
    var relY: Double
    var relW: Double
    var relH: Double
    /// Order of the window within its app at capture time.
    var slot: Int

    var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// Convenience factory used by the capturer and split builder: derives
    /// display slot and relative frame automatically.
    static func make(bundleID: String, appName: String, title: String, frame: CGRect, slot: Int) -> WindowSnapshot {
        WindowSnapshot(bundleID: bundleID, appName: appName, title: title, frame: frame, slot: slot)
    }

    enum CodingKeys: String, CodingKey {
        case id, bundleID, appName, title, x, y, width, height
        case displaySlot, relX, relY, relW, relH, slot
    }

    init(bundleID: String, appName: String, title: String, frame: CGRect, slot: Int) {
        self.id = UUID()
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.x = frame.minX
        self.y = frame.minY
        self.width = frame.width
        self.height = frame.height
        let displaySlot = ScreenLayout.slot(for: frame)
        self.displaySlot = displaySlot
        let container = ScreenLayout.visibleFrame(atSlot: displaySlot)
        let rel = ScreenLayout.relative(frame, in: container)
        self.relX = rel.relX
        self.relY = rel.relY
        self.relW = rel.relW
        self.relH = rel.relH
        self.slot = slot
    }

    /// Legacy-compatible decoding: layouts stored by v1 lack the display
    /// fields; they fall back to absolute-only restore.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleID = try container.decode(String.self, forKey: .bundleID)
        appName = try container.decode(String.self, forKey: .appName)
        title = try container.decode(String.self, forKey: .title)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        displaySlot = try container.decodeIfPresent(Int.self, forKey: .displaySlot) ?? 0
        relX = try container.decodeIfPresent(Double.self, forKey: .relX) ?? 0
        relY = try container.decodeIfPresent(Double.self, forKey: .relY) ?? 0
        relW = try container.decodeIfPresent(Double.self, forKey: .relW) ?? 1
        relH = try container.decodeIfPresent(Double.self, forKey: .relH) ?? 1
        slot = try container.decodeIfPresent(Int.self, forKey: .slot) ?? 0
    }
}

enum LayoutKind: String, Codable {
    case capture
    case split
}

struct SavedLayout: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var createdAt: Date
    var windows: [WindowSnapshot]
    /// Display arrangement at capture time (sorted by X).
    var displays: [DisplaySnapshot]
    var kind: LayoutKind

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, windows, displays, kind
    }

    init(id: UUID = UUID(), name: String, createdAt: Date, windows: [WindowSnapshot], displays: [DisplaySnapshot] = [], kind: LayoutKind = .capture) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.windows = windows
        self.displays = displays
        self.kind = kind
    }

    /// Legacy-compatible decoding for layouts.json files from v1.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        windows = try container.decode([WindowSnapshot].self, forKey: .windows)
        displays = try container.decodeIfPresent([DisplaySnapshot].self, forKey: .displays) ?? []
        kind = try container.decodeIfPresent(LayoutKind.self, forKey: .kind) ?? .capture
    }

    var appBundles: [String] {
        var seen = Set<String>()
        return windows.compactMap { snapshot in
            guard seen.insert(snapshot.bundleID).inserted else { return nil }
            return snapshot.bundleID
        }
    }
}
