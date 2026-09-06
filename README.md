# Layouts

Save your current window arrangement, bring it back later with one click or a
global hotkey. Native macOS menubar app built on the Accessibility API.

## Features

- **Capture** — snapshots every regular on-screen window (app bundle ID, title,
  frame, stacking slot) into a named, editable layout. A capture sheet lets you
  exclude individual windows before saving.
- **Restore** — relaunches apps that aren't running (waits up to 6 s for their
  windows to materialize), matches windows by title first and stacking order
  second, then moves/resizes them via the Accessibility API. Frames are clamped
  into the target screen's visible area, so layouts captured on a big display
  still land fully on-screen.
- **Global hotkeys** — ⌥⌘⌃ + 1…9 restores the first nine layouts system-wide
  (Carbon `RegisterEventHotKey`, toggle in Settings).
- **Management** — rename (inline alert), duplicate, delete (with
  confirmation), double-click or Restore button to apply.
- **Permission flow** — the panel shows a persistent banner until Accessibility
  is granted; "Grant" triggers the system prompt and the banner clears itself
  once approved (status polling).
- **States** — restore progress banner ("Launching Safari…", "Restored 5 of 6
  windows"), empty state with a capture CTA.

## Build & run

```bash
cd Layouts
./Scripts/make_app.sh          # → dist/Layouts.app
open dist/Layouts.app
```

`swift run` works for development; the bundle is needed for launch-at-login.
Opening `Package.swift` in Xcode works too.

**Permissions**: requires Accessibility (System Settings → Privacy & Security →
Accessibility). The app prompts for it on first restore/capture.

## Design notes (ui-craft)

- Same native-first family as PortPatrol: system materials, single cobalt
  accent, radius 6/8, monospaced numerals, density 6, motion 2.
- Hierarchy: Capture is the only prominent (filled) action; per-row Restore is
  small-filled, everything else is ghost/menu.
- Destructive actions are confirmed; restore is cancellable by nature (it's
  just window moves) so it has no confirm.

## Architecture

- `AXBridge` — the only file that talks to the Accessibility API (read windows,
  titles, frames; set frames; raise; trust checks).
- `LayoutCapturer` — snapshot current arrangement.
- `LayoutRestorer` — launch → wait → match → move, with live status text.
- `LayoutStore` — `@Observable` CRUD, JSON persistence in
  `~/Library/Application Support/Layouts/layouts.json`.
- `HotKeyManager` — Carbon hotkeys → digit callback → restore.

## Known tradeoffs

- Windows that were fullscreen at capture time are restored as normal windows
  (AX can't re-enter macOS fullscreen).
- Minimized windows are excluded from captures.
- Apps that restore no windows on launch (or show a document picker) may leave
  fewer matched windows than captured; the status banner reports the count.
