# Status

## Goal

Soprano Cast: a copy of Raycast's Root Search and hotkeys in the Soprano family, Mission
Control chrome. Hotkeys behave exactly like Raycast's (`⌘1` opens Google Chrome, `⌘Space`
opens the launcher). Full phase-1 scope: Root Search with favorites, suggestions,
aliases, calculator, fallbacks, arguments and history; the Action Panel; global hotkeys of
every Raycast shape and the Hyper key; system commands; window management; quicklinks;
Raycast-format script commands; command line. `docs/ROADMAP.md` lists what is deliberately
not copied.

## In progress (phase 1)

All modules are being written in parallel against `docs/ARCHITECTURE.md`:

- Core (`SopranoCastCore`): key and hotkey parsing, recorder, modifier gesture detector,
  conflicts; settings resolver, template and comment-preserving editor; search matcher,
  ranker, frecency, search history, calculator; built-in items, item actions, quicklink
  templates, script metadata and output, window layout; launcher key router and result
  navigator.
- System: app catalog, icons, app actions, quicklink opener, system command runner,
  script catalog and runner, item runner, window manager, hotkey center (Carbon + event
  tap), keyboard layout, Hyper key.
- Launcher: `LauncherController`, model builder, `LauncherWindow` with search bar, list,
  footer, Action Panel, recorder, alias editor, confirmation, output and HUD.
- Shell: app delegate, menu bar, login item, settings and theme centers, app state store,
  permissions window, CLI server/client.
- Fixtures and the offscreen `snapshot` harness; packaging, signing and sync scripts;
  docs.

## Next

1. Verify: `swift build`, `swift test`, fix-ups across modules.
2. Raycast import from Furkan's `.rayconfig` (hotkeys, aliases, favorites, quicklinks).
3. Visual QA with the `snapshot` harness (root, results, calculator, Action Panel,
   recorder, alias editor, confirmation, output, HUD).
4. Install, quit Raycast (or clear its hotkey), grant Accessibility, first live run.

## Open decisions

- Physical-key hotkeys (Raycast's default) are recorded as key equivalents on the current
  layout: a character hotkey stores the character the key types without modifiers and is
  re-resolved to a key code whenever the input source changes.
