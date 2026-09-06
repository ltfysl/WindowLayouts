import AppKit
import SwiftUI

struct LayoutsListView: View {
    let store: LayoutStore
    let restorer: LayoutRestorer

    @State private var axTrusted = AXBridge.isTrusted
    @State private var renameTarget: SavedLayout?
    @State private var renameText = ""
    @State private var deleteTarget: SavedLayout?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if axTrusted {
                if restorer.isRestoring || !restorer.statusText.isEmpty {
                    RestoreBanner(restorer: restorer)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
                content
            } else {
                PermissionCard
            }
            footer
        }
        .frame(width: 470)
        .frame(minHeight: 400, idealHeight: 540, maxHeight: 640)
        .task { await watchTrustStatus() }
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x2")
                .foregroundStyle(Tokens.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("Layouts").font(.headline)
                Text("Click a card to restore")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            HoverButton(systemImage: "rectangle.split.2x1", help: "Quick Split — arrange apps into halves/thirds") {
                SplitWindowController.shared.show(store: store)
            }
            .disabled(!axTrusted)
            HoverButton(systemImage: "plus.viewfinder", help: "Capture current windows") {
                CaptureWindowController.shared.show(store: store)
            }
            .disabled(!axTrusted)
            HoverButton(systemImage: "gearshape", help: "Settings") { openSettings() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.layouts.isEmpty {
            VStack(spacing: 12) {
                ContentUnavailableView {
                    Label("No layouts yet", systemImage: "rectangle.on.rectangle.slash")
                } description: {
                    Text("Arrange your windows, then capture the arrangement — or build a split from a template.")
                }
                HStack(spacing: 8) {
                    Button {
                        CaptureWindowController.shared.show(store: store)
                    } label: {
                        Label("Capture Windows", systemImage: "plus.viewfinder")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        SplitWindowController.shared.show(store: store)
                    } label: {
                        Label("Quick Split", systemImage: "rectangle.split.2x1")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(store.layouts.enumerated()), id: \.element.id) { index, layout in
                        LayoutCard(
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
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(minHeight: 300)
        }
    }

    // MARK: - Permission card (replaces the silent dead-state)

    private var PermissionCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Accessibility required")
                .font(.headline)
            Text("Layouts reads and moves windows through the Accessibility API. Grant access once — then click any card to restore the arrangement.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button {
                AXBridge.promptForTrust()
            } label: {
                Label("Grant Accessibility", systemImage: "hand.tap.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("If you already granted it, the panel re-enables itself within seconds.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(axTrusted ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(axTrusted
                 ? (restorer.statusText.isEmpty ? "Ready · ⌥⌘⌃1–9 restores hotkeys" : restorer.statusText)
                 : "Waiting for Accessibility permission…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
    }

    private func watchTrustStatus() async {
        while !Task.isCancelled {
            let trusted = AXBridge.isTrusted
            if axTrusted != trusted {
                axTrusted = trusted
            }
            // Granted → stop polling for this panel session.
            if trusted { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

// MARK: - Card

private struct LayoutCard: View {
    let layout: SavedLayout
    let hotkeyDigit: Int?
    let isBusy: Bool
    let onRestore: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onRestore) {
            cardContent
        }
        .buttonStyle(LayoutCardButtonStyle(isHovered: isHovered))
        .overlay(alignment: .topTrailing) {
            kebabMenu.padding(6)
        }
        .onHover { isHovered = $0 }
        .disabled(isBusy)
        .help("Click to restore this layout")
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var cardContent: some View {
        HStack(spacing: 12) {
            LayoutThumb(layout: layout)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if layout.kind == .split {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.caption2)
                            .foregroundStyle(Tokens.accent)
                    }
                    Text(layout.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if layout.displays.count > 1 {
                    Text("Multi-monitor layout")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)

            if let digit = hotkeyDigit {
                Text("⌥⌘⌃\(digit)")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            }
        }
        .padding(10)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var subtitle: String {
        var parts = ["\(layout.windows.count) windows", "\(layout.appBundles.count) apps"]
        if layout.displays.count > 1 {
            parts.append("\(layout.displays.count) displays")
        }
        return parts.joined(separator: " · ")
    }

    private var kebabMenu: some View {
        Menu {
            Button("Restore") { onRestore() }
            Divider()
            Button("Rename…", action: onRename)
            Button("Duplicate", action: onDuplicate)
            Divider()
            Button("Delete…", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.35))
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Card button style: hover fill + accent border, pressed feedback.
struct LayoutCardButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(isHovered ? 0.07 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isHovered ? Tokens.accent.opacity(0.6) : Color.primary.opacity(0.10),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Banners

private struct RestoreBanner: View {
    let restorer: LayoutRestorer

    var body: some View {
        HStack(spacing: 8) {
            if restorer.isRestoring {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
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

// MARK: - Small icon button (rest, hover, disabled)

struct HoverButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered && isEnabled ? Tokens.accent : Color.secondary)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.controlCornerRadius)
                        .fill(Color.primary.opacity(isHovered && isEnabled ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}
