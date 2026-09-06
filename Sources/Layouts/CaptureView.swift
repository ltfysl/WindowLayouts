import AppKit
import SwiftUI

struct CaptureView: View {
    let store: LayoutStore
    /// Called instead of dismiss when hosted in a standalone window.
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [WindowSnapshot] = []
    @State private var excluded: Set<UUID> = []
    @State private var name = ""
    @State private var isScanning = false

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var included: [WindowSnapshot] {
        snapshots.filter { !excluded.contains($0.id) }
    }

    private var groups: [(appName: String, bundleID: String, windows: [WindowSnapshot])] {
        Dictionary(grouping: snapshots, by: \.bundleID)
            .map { (appName: $0.value.first?.appName ?? "Unknown", bundleID: $0.key, windows: $0.value) }
            .sorted { $0.appName < $1.appName }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            windowList
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 460, height: 480)
        .task { recapture() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.viewfinder")
                .foregroundStyle(.secondary)
            Text("Capture Window Layout")
                .font(.headline)
            Spacer()
            if isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Recapture") { recapture() }
                .controlSize(.small)
                .disabled(isScanning)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var windowList: some View {
        if snapshots.isEmpty {
            ContentUnavailableView {
                Label("No windows found", systemImage: "rectangle.dashed")
            } description: {
                Text("Open a few windows, then press Recapture.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.bundleID) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                appIcon(for: group.bundleID)
                                Text(group.appName)
                                    .font(.callout.weight(.semibold))
                                Text("\(group.windows.count)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(group.windows) { snapshot in
                                WindowToggleRow(
                                    snapshot: snapshot,
                                    isIncluded: Binding(
                                        get: { !excluded.contains(snapshot.id) },
                                        set: { isOn in
                                            if isOn {
                                                excluded.remove(snapshot.id)
                                            } else {
                                                excluded.insert(snapshot.id)
                                            }
                                        }
                                    )
                                )
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            TextField("Layout name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("\(included.count) of \(snapshots.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
            Button("Cancel") { close() }
            Button("Save Layout", action: save)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || included.isEmpty)
        }
        .padding(14)
    }

    /// Metadata pass on main, parallel AX reads off-main — the window never
    /// freezes even with many apps.
    private func recapture() {
        guard !isScanning else { return }
        isScanning = true
        let appInfos = LayoutCapturer.appInfos()
        Task {
            let captured = await LayoutCapturer.captureCurrentWindows(appInfos: appInfos)
            snapshots = captured
            excluded.removeAll()
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                name = "Layout " + Date.now.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            }
            isScanning = false
        }
    }

    private func save() {
        let layout = SavedLayout(
            name: name.trimmingCharacters(in: .whitespaces),
            createdAt: .now,
            windows: included
        )
        store.add(layout)
        close()
    }

    @ViewBuilder
    private func appIcon(for bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 18, height: 18)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct WindowToggleRow: View {
    let snapshot: WindowSnapshot
    @Binding var isIncluded: Bool

    var body: some View {
        Toggle(isOn: $isIncluded) {
            HStack(spacing: 8) {
                Image(systemName: "macwindow")
                    .foregroundStyle(.secondary)
                Text(snapshot.title.isEmpty ? "Untitled window" : snapshot.title)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(snapshot.width)) × \(Int(snapshot.height))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }
}
