# Status

## Goal

Soprano Cast: a copy of Raycast's Root Search and hotkeys in the Soprano family, Folio
chrome. Hotkeys behave exactly like Raycast's (`⌘1` opens Google Chrome, `⌘Space`
opens the launcher). Full phase-1 scope: Root Search with favorites, suggestions,
aliases, calculator, fallbacks, arguments and history; the Action Panel; global hotkeys of
every Raycast shape and the Hyper key; system commands; window management; quicklinks;
Raycast-format script commands; command line. `docs/ROADMAP.md` lists what is deliberately
not copied.

## Done (phase 1)

- Core (`SopranoCastCore`): key and hotkey parsing (named, physical and character keys),
  recorder, modifier gesture detector, conflicts; settings resolver with per-key warnings,
  commented template and comment-preserving editor; search matcher, ranker, frecency,
  search history, calculator; built-in items, item actions, quicklink templates, script
  metadata and output, window layout; launcher key router and result navigator.
- System: app catalog (Spotlight plus a direct scan), icons, app actions, quicklink opener,
  system command runner, script catalog and runner, item runner, window manager, hotkey
  center (Carbon + event tap, re-registered on layout changes), keyboard layout, Hyper key.
- Launcher: `LauncherController`, model builder, `LauncherWindow` with search bar, list,
  footer, Action Panel, recorder, alias editor, confirmation, output and HUD.
- Shell: app delegate, menu bar, login item, settings and theme centers, app state store,
  permissions window, CLI server/client.
- Fixtures and the offscreen `snapshot` harness; packaging, signing and sync scripts;
  docs.
- Builds; 393 tests pass. Visual QA through the `snapshot` harness done (root, results,
  calculator, Action Panel, recorder with conflicts, alias editor, confirmation, output,
  arguments, fallbacks).
- Window layout: Move Up / Down / Left / Right center along the edge; Previous / Next
  Display keep the aspect ratio (Raycast's "Center Window" / "Keep Aspect Ratio").
- The user's Raycast setup, read from Raycast's Settings window, is migrated into
  `~/.config/soprano-cast/settings.json`: the user's 11 app hotkeys (by key position,
  `key:`), `windowManagement.halves: cycleSizes` and `app.showMenuBarIcon: false`; Raycast's
  other settings already equal the defaults.
- Settings window (branch `feat/settings-window`): Raycast's Settings layout in Soprano's
  settings chrome — General (settings.json card with warnings, login, launcher hotkey,
  menu bar icon, theme, ordered favorites and fallbacks), Extensions (grouped command
  table with alias, hotkey and Enabled per row, filter, detail pane for favorites,
  fallbacks, quicklinks, script and app folders, window management) and Advanced (screen,
  pop to root, navigation, focus loss, Hyper key). `⌘,`, Settings… and the Settings
  command open it; the file stays the source of truth (live both ways). The launcher's
  recorder logic moved into Core (`HotkeyRecordingSession`) and is shared with the window;
  quicklink edits keep every other entry of the raw array. 416 tests pass; every tab,
  group pane, the recorder (with a conflict) and a realistic settings file checked in the
  `--settings-window` snapshots.
- Folio (branch `feat/folio-design`): Soprano's Folio design system vendored
  (`Chrome.swift`, `Theme.swift`; Departure Mono and the Mission Control chrome removed).
  Launcher, Action Panel, recorder, alias editor, confirmation, output, HUD, settings
  window and permissions window restyled to `b/cast.html` / `b/cast-settings.html`;
  hotkeys as K1 caps; Folio Paper / Ink with `folio` following the system and Follow
  Soprano following Soprano's theme and appearance; Folio menu-bar glyph and app icon.
  460 tests pass; snapshots checked in Paper and Ink against the mockups.

## Next

1. First live run by the user: quit Raycast (and remove it from login items), start
   Soprano Cast, grant Accessibility, use the migrated hotkeys and Root Search on the real
   desktop (both keyboard layouts, several displays).
2. Fixes from that run.

## Open decisions

- Known upstream issue: the vendored `JSONCText` `removing` drops a trailing comment on the
  line before a removed last object member (e.g. Remove Hotkey on the last entry of
  `hotkeys`). The fix belongs in Soprano; then re-run `scripts/sync-soprano-chrome.sh`.
- Raycast `.rayconfig` import waits for a real export file to build against.
