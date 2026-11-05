# Roadmap

Soprano Cast copies Raycast's Root Search and hotkeys. What is left out, and why, is listed
below, followed by what is not built yet.

## Not copied (family conventions)

- Cloud Sync.
- The Raycast account.
- AI.
- The extension Store.
- Raycast themes: Soprano's themes instead (Folio Paper / Ink and seven dark themes).

## Not built yet

- Raycast `.rayconfig` import — needs a real export to build against (Raycast 1.70's
  export never wrote a file).
- Sub-pane items like Raycast's "Keyboard Shortcuts", Accessibility "Zoom" or "Current
  Network Details", which open anchors such as
  `x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts` — the anchors are
  undocumented and change between macOS versions.

## Later

- Clipboard history.
- Snippets.
- File search.
- Floating notes.
- Emoji picker.
- Window layouts and custom window commands.
- Move window to a Space.
- Resize / Move Window with typed values.
- Unit and currency conversion.

## Linux (Omarchy)

Furkan moves to Omarchy (Arch Linux, Hyprland, Wayland) later. Today only macOS builds.

- First decide: port Soprano Cast, or theme and extend Omarchy's own launcher (Walker).
- `SopranoCastCore` (about 5,800 lines, Foundation and CoreGraphics) is the part to keep: build
  it on Linux (Swift through `swiftly`), with its own test target and a Linux CI job.
- macOS-only, each needs a Linux route:
  - Global hotkeys and the Hyper key (`RegisterEventHotKey`, `CGEvent` taps): Wayland lets no
    app grab keys, so bind them in `hyprland.conf` to a `soprano-cast` command.
  - App search (`NSWorkspace`, `NSMetadataQuery`): XDG `.desktop` files.
  - Window commands (AX): Hyprland IPC (`hyprctl dispatch`, `hyprctl clients -j`).
  - Battery and IOKit commands: `/sys/class/power_supply`, `upower`.
  - Login item (`SMAppService`): `exec-once` in Hyprland or a systemd user unit.
- The UI (about 16,800 lines of AppKit) is rebuilt on the toolkit chosen once for the family,
  in Soprano first (every app syncs its chrome from there).
