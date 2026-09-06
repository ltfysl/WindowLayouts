import AppKit
import SwiftUI

/// Quick split builder: pick a template, assign apps to slots, done — no
/// manual arranging. Produces a regular SavedLayout that restores like any
/// captured layout (including multi-monitor scaling).
struct SplitBuilderView: View {
    let store: LayoutStore

    @Environment(\.dismiss) private var dismiss

    enum Template: String, CaseIterable, Identifiable {
        case leftRight = "Left | Right"
        case topBottom = "Top / Bottom"
        case thirds = "Thirds"

        var id: String { rawValue }
        var slotCount: Int { self == .thirds ? 3 : 2 }
    }

    struct AppOption: Identifiable, Hashable {
        let name: String
        let bundleID: String
        var id: String { bundleID }
    }

    @State private var template: Template = .leftRight
    @State private var ratio: Double = 0.5
    @State private var displaySlot = 0
    @State private var selections: [Int: AppOption] = [:]
    @State private var customName = ""

    private var apps: [AppOption] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .compactMap { app -> AppOption? in
                guard let bundle = app.bundleIdentifier, seen.insert(bundle).inserted else { return nil }
                return AppOption(name: app.localizedName ?? bundle, bundleID: bundle)
            }
            .sorted { $0.name < $1.name }
    }

    private var chosenCount: Int {
        (0..<template.slotCount).filter { selections[$0] != nil }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            HStack(alignment: .top, spacing: 16) {
                Form {
                    Picker("Template", selection: $template) {
                        ForEach(Template.allCases) { template in
                            Text(template.rawValue).tag(template)
                        }
                    }
                    .pickerStyle(.segmented)

                    if template != .thirds {
                        HStack {
                            Text("Ratio")
                            Slider(value: $ratio, in: 0.3...0.7)
                            Text("\(Int(ratio * 100))%")
                                .monospacedDigit()
                                .frame(width: 38, alignment: .trailing)
                        }
                    }

                    Picker("Display", selection: $displaySlot) {
                        ForEach(Array(ScreenLayout.sortedByX.enumerated()), id: \.offset) { index, screen in
                            Text(displayLabel(index, screen)).tag(index)
                        }
                    }

                    ForEach(0..<template.slotCount, id: \.self) { slot in
                        slotPicker(slot)
                    }

                    TextField("Name (optional)", text: $customName)
                        .textFieldStyle(.roundedBorder)
                }
                .formStyle(.grouped)

                VStack {
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LayoutThumb(layout: previewLayout)
                        .frame(width: 140, height: 84)
                    Spacer()
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 4)

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Split", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(chosenCount == 0)
            }
            .padding(14)
        }
        .frame(width: 560, height: 440)
        .onAppear {
            if displaySlot >= ScreenLayout.sortedByX.count {
                displaySlot = 0
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x1").foregroundStyle(.secondary)
            Text("Quick Split").font(.headline)
            Text("Arranges app windows without manual dragging — saves as a normal layout.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func slotPicker(_ slot: Int) -> some View {
        Picker("Slot \(slot + 1)", selection: Binding(
            get: { selections[slot] },
            set: { selections[slot] = $0 }
        )) {
            Text("Empty").tag(AppOption?.none)
            ForEach(apps) { app in
                Text(app.name).tag(AppOption?.some(app))
            }
        }
    }

    private func displayLabel(_ index: Int, _ screen: NSScreen) -> String {
        var label = index == 0 ? "Main" : "Display \(index + 1)"
        label += " (\(Int(screen.frame.width))×\(Int(screen.frame.height)))"
        return label
    }

    // MARK: - Layout construction

    private func slotFrames(in visible: CGRect) -> [CGRect] {
        switch template {
        case .leftRight:
            let splitX = visible.minX + visible.width * ratio
            return [
                CGRect(x: visible.minX, y: visible.minY, width: visible.width * ratio, height: visible.height),
                CGRect(x: splitX, y: visible.minY, width: visible.width * (1 - ratio), height: visible.height),
            ]
        case .topBottom:
            let splitY = visible.minY + visible.height * ratio
            return [
                CGRect(x: visible.minX, y: splitY, width: visible.width, height: visible.height * ratio),
                CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height * (1 - ratio)),
            ]
        case .thirds:
            let third = visible.width / 3
            return [
                CGRect(x: visible.minX, y: visible.minY, width: third, height: visible.height),
                CGRect(x: visible.minX + third, y: visible.minY, width: third, height: visible.height),
                CGRect(x: visible.minX + 2 * third, y: visible.minY, width: third, height: visible.height),
            ]
        }
    }

    private func buildLayout() -> SavedLayout {
        let frames = slotFrames(in: ScreenLayout.visibleFrame(atSlot: displaySlot))
        var windows: [WindowSnapshot] = []
        for slot in 0..<template.slotCount {
            guard let app = selections[slot] else { continue }
            windows.append(WindowSnapshot.make(
                bundleID: app.bundleID,
                appName: app.name,
                title: "<split \(slot + 1)>",
                frame: frames[slot],
                slot: windows.count
            ))
        }
        let slotNames = (0..<template.slotCount).compactMap { selections[$0]?.name }
        let autoName = "Split · " + slotNames.joined(separator: " | ")
        let name = customName.trimmingCharacters(in: .whitespaces).isEmpty
            ? autoName
            : customName.trimmingCharacters(in: .whitespaces)
        return SavedLayout(
            name: name,
            createdAt: .now,
            windows: windows,
            displays: ScreenLayout.snapshots(),
            kind: .split
        )
    }

    private var previewLayout: SavedLayout {
        buildLayout()
    }

    private func create() {
        let layout = buildLayout()
        guard !layout.windows.isEmpty else { return }
        store.add(layout)
        dismiss()
    }
}
