import SwiftUI

struct LayoutsListView: View {
    let store: LayoutStore
    let restorer: LayoutRestorer

    @State private var axTrusted = AXBridge.isTrusted
    @State private var isCapturing = false
    @State private var isBuildingSplit = false
    @State private var renameTarget: SavedLayout?
    @State private var renameText = ""
    @State private var deleteTarget: SavedLayout?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if !axTrusted {
                PermissionBanner()
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
            if restorer.isRestoring || !restorer.statusText.isEmpty {
                RestoreBanner(restorer: restorer)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
            content
        }
        .frame(width: 430)
        .frame(maxHeight: 580)
        .task { await watchTrustStatus() }
        .sheet(isPresented: $isCapturing) {
            CaptureView(store: store)
        }
        .sheet(isPresented: $isBuildingSplit) {
            SplitBuilderView(store: store)
        }
        .alert("Rename Layout", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                guard var layout = renameTarget else { return }
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    layout.name = trimmed
                    store.update(layout)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(
            "Delete “\(deleteTarget?.name ?? "")”?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { layout in
            Button("Delete", role: .destructive) { store.delete(layout) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Your windows won't be touched. This can't be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x2")
                .foregroundStyle(.secondary)
            Text("Window Layouts")
                .font(.headline)
            Spacer()
            Button {
                isBuildingSplit = true
            } label: {
                Label("Split", systemImage: "rectangle.split.2x1")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .disabled(!axTrusted || restorer.isRestoring)
            Button {
                isCapturing = true
            } label: {
                Label("Capture", systemImage: "plus.viewfinder")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .disabled(!axTrusted || restorer.isRestoring)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if store.layouts.isEmpty {
            VStack(spacing: 12) {
                ContentUnavailableView {
                    Label("No layouts yet", systemImage: "rectangle.on.rectangle.slash")
                } description: {
                    Text("Arrange your windows, then capture the arrangement to bring it back any time.")
                }
                Button("Capture Current Windows") {
                    isCapturing = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!axTrusted)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(store.layouts.enumerated()), id: \.element.id) { index, layout in
                        LayoutRow(
                            layout: layout,
                            hotkeyDigit: index < 9 ? index + 1 : nil,
                            isBusy: restorer.isRestoring,
                            onRestore: { Task { await restorer.restore(layout) } },
                            onRename: {
                                renameTarget = layout
                                renameText = layout.name
                            },
                            onDuplicate: { store.duplicate(layout) },
                            onDelete: { deleteTarget = layout }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    private func watchTrustStatus() async {
        while !Task.isCancelled {
            axTrusted = AXBridge.isTrusted
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

private struct LayoutRow: View {
    let layout: SavedLayout
    let hotkeyDigit: Int?
    let isBusy: Bool
    let onRestore: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var subtitle: String {
        var parts = ["\(layout.windows.count) windows", "\(layout.appBundles.count) apps"]
        if layout.displays.count > 1 {
            parts.append("\(layout.displays.count) displays")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            LayoutThumb(layout: layout)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if layout.kind == .split {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.caption2)
                            .foregroundStyle(Tokens.accent)
                    }
                    Text(layout.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let digit = hotkeyDigit {
                Text("⌥⌘⌃\(digit)")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.05))
                    )
            }

            Button("Restore", action: onRestore)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

            Menu {
                Button("Rename…", action: onRename)
                Button("Duplicate", action: onDuplicate)
                Divider()
                Button("Delete…", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(isBusy)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Tokens.rowCornerRadius)
                .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: Tokens.rowCornerRadius))
        .onHover { isHovered = $0 }
        // One click restores the whole arrangement ("bei Klick setzt er das zurück").
        .onTapGesture { onRestore() }
        .help("Click to restore this layout")
    }
}

private struct AppIconStack: View {
    let bundles: [String]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(bundles.prefix(4).enumerated()), id: \.offset) { index, bundleID in
                icon(for: bundleID)
                    .zIndex(Double(10 - index))
            }
        }
        .frame(width: 52)
    }

    @ViewBuilder
    private func icon(for bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 22, height: 22)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct PermissionBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility permission needed")
                    .font(.callout.weight(.medium))
                Text("Layouts reads and moves windows through the Accessibility API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant") { AXBridge.promptForTrust() }
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Tokens.controlCornerRadius).fill(Color.orange.opacity(0.12)))
    }
}

private struct RestoreBanner: View {
    let restorer: LayoutRestorer

    var body: some View {
        HStack(spacing: 8) {
            if restorer.isRestoring {
                ProgressView()
                    .controlSize(.small)
            }
            Text(restorer.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Tokens.controlCornerRadius)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
