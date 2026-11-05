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

Furkan wechselt später auf Omarchy (Arch Linux, Hyprland, Wayland). Heute baut die App nur auf
macOS.

- Zuerst entscheiden: Soprano Cast portieren oder Omarchys eigenen Launcher (Walker) thematisieren
  und erweitern.
- `SopranoCastCore` (etwa 5.800 Zeilen, Foundation und CoreGraphics) bleibt: auf Linux bauen
  (Swift über `swiftly`), mit eigenem Testtarget und einem Linux-CI-Job.
- Nur auf macOS vorhanden, jeweils mit Linux-Weg:
  - Globale Hotkeys und die Hyper-Taste (`RegisterEventHotKey`, `CGEvent`-Taps): Unter Wayland
    darf keine App Tasten abgreifen, also in `hyprland.conf` an einen `soprano-cast`-Befehl binden.
  - App-Suche (`NSWorkspace`, `NSMetadataQuery`): XDG-`.desktop`-Dateien.
  - Fensterbefehle (AX): Hyprland-IPC (`hyprctl dispatch`, `hyprctl clients -j`).
  - Akku- und IOKit-Befehle: `/sys/class/power_supply`, `upower`.
  - Anmeldeobjekt (`SMAppService`): `exec-once` in Hyprland oder eine systemd-User-Unit.
- Die UI (etwa 16.800 Zeilen AppKit) wird auf dem Toolkit neu gebaut, das einmal für die ganze
  Familie gewählt wird, zuerst in Soprano (jede App synct ihr Chrome von dort).
