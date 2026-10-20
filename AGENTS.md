# Soprano Cast

Keyboard launcher for macOS in the Soprano family: a copy of Raycast's Root Search and
hotkeys (global hotkeys of every Raycast type on any command, aliases, favorites, the Action
Panel, window management, system commands, quicklinks, Raycast-format script commands, an
inline calculator) in Soprano's "Mission Control" chrome. Swift 6 + programmatic AppKit (no
storyboards/xibs/SwiftUI), SPM, macOS 14+, menu-bar app (no Dock icon). Shipped as a
hand-packaged `.app` via `scripts/install.sh`. GitHub:
[`frknue/soprano_cast`](https://github.com/frknue/soprano_cast) (public).

## Commands

Homebrew Swift with the Command Line Tools SDK. Xcode's newer SDK breaks Homebrew Swift,
so pin `DEVELOPER_DIR` on every direct Swift command:

```bash
export DEVELOPER_DIR=/Library/Developer/CommandLineTools PATH="/opt/homebrew/opt/swift/bin:$PATH"
swift build
swift test
swift test --filter LauncherKeyRouterTests
./scripts/dev.sh --build-only        # package .build/debug/Soprano Cast Dev.app (com.soprano.cast.dev)
./scripts/install.sh                 # release build → /Applications/Soprano Cast.app
.build/debug/SopranoCast snapshot --out /tmp/cast.png --query "chr" --report /tmp/cast.json
.build/debug/SopranoCast snapshot --out /tmp/rec.png --query "chrome" --keys "shift+cmd+, return rec:cmd+1 wait" --report /tmp/rec.json
.build/debug/SopranoCast snapshot --out /tmp/settings.png --settings-window extensions --select app:com.google.Chrome --report /tmp/settings.json
.build/debug/SopranoCast list        # no bundle → port com.soprano.cast.cli: talks to the INSTALLED app
```

`ld: warning: building for macOS-14.0 …` link warnings are expected. There is no linter or
formatter; match surrounding style.

## Verification

- Verify source changes with `swift build` and `swift test`.
- Verify UI only with the offscreen `snapshot` subcommand and read the PNG. It builds the
  real `LauncherController` and `LauncherWindow` on fixtures (14 apps, 3 script commands,
  5 System Settings panes, fixed time, usage and history), with no Dock icon, hotkey,
  permission or persisted state; `--report` writes query, row ids, selected id, overlay, footer toast, the
  runner's log and settings edits as JSON. `--settings-window <tab>` renders the settings
  window on the same fixtures instead. Virtual time stands still unless a `wait` token lets
  it pass, so a recorded hotkey only saves after `wait`. Usage (`SnapshotCommand.usage`):

  ```text
  usage: SopranoCast snapshot --out <png> [--query "<text>"] [--keys "<token> …"]
                              [--settings <jsonc>] [--screen 1512x982] [--theme <id>]
                              [--report <json>]
         SopranoCast snapshot --out <png> --settings-window <general|extensions|advanced>
                              [--select <item-id|group:<group>>] [--filter "<text>"]
                              [--record <item-id|launcher>] [--keys "<token> …"]
                              [--settings <jsonc>] [--theme <id>] [--report <json>]
    --settings-window renders the settings window (1120x700) instead of the launcher;
      --select picks a row of Extensions (group:applications, group:quicklinks,
      group:scriptCommands, group:sopranoCast, group:system, group:systemSettings,
      group:windowManagement or an item id), --filter searches its table, --record
      opens the recorder card and --keys replay into it.
    --keys tokens, separated by spaces, replayed after --query:
      named keys   return enter esc escape tab space delete backspace forwardDelete
                   up down left right home end pageUp pageDown f1 … f20
      characters   one character types it when the launcher doesn't use it
                   ("A" = shift+a, "!" = shift+1; US keyboard)
      key:<name>   a printable key by position: key:' key:z key:0x27 (cmd+key:')
      modifiers    cmd shift opt ctrl fn joined with "+" before a key:
                   cmd+k cmd+return opt+return shift+tab shift+cmd+, cmd+f cmd+esc ctrl+n
      rec:<hotkey> the key events that record a settings.json hotkey in the recorder:
                   rec:cmd+1 rec:hyper+k rec:rcmd rec:cmd+opt rec:double:cmd rec:both:shift
      wait         lets 2000 ms pass (the recorder's countdown saves); wait:<ms> any span.
                   Without it time stands still: scheduled work (countdowns, toast
                   timeouts) never runs.
  ```
- Never launch the GUI or run `./scripts/dev.sh` without `--build-only` unless the user
  asks: the app grabs `⌘Space` and every configured global hotkey system-wide, may remap
  a key with `hidutil` for the Hyper key, and asks for Accessibility.

## Installing completed changes

After a verified change to the app or its packaging, run `./scripts/install.sh` as the last
step. It replaces `/Applications/Soprano Cast.app` without restarting a running instance.
Never use `sudo`; report permission problems instead. Docs-only work needs no install.

## Commits and changelog

- Push, open PRs, or create tags only when the user asks for that remote action.
- Short imperative subjects, `feat:` / `fix:` / `docs:` / `test:` / `chore:` prefixes.
- User-visible changes get a line under `## [Unreleased]` in `CHANGELOG.md` (Keep a
  Changelog groups: Added, Changed, Deprecated, Removed, Fixed, Security), written for the
  user and naming the shortcut or setting. Never add a version heading during feature work.
- Releases: rename `[Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`, add a fresh `[Unreleased]`,
  set `CFBundleShortVersionString` and `CFBundleVersion` in `Support/Info.plist` (the only
  version source), `swift test`, install, commit `release: vX.Y.Z`.

## Architecture

`docs/ARCHITECTURE.md` is the contract: modules and file ownership, the contract files,
binding Core signatures, settings schema and resolution rules, the key map, system APIs,
launcher behavior, harness options and the visual spec. Keep it current when a seam,
setting, key or harness option changes. `docs/ROADMAP.md` lists what is deliberately not
copied or not built yet; `docs/STATUS.md` the current state.

- `Sources/SopranoCastCore/` — pure logic, Foundation + CoreGraphics, no AppKit: items,
  keys and hotkeys (parsing, recorder, gesture detection, conflicts), settings, search and
  ranking, calculator, quicklink templates, script metadata, window layout math, launcher
  key routing and list navigation, CLI messages.
- `Sources/SopranoCast/System/` — the live macOS layer: app catalog, icons, app /
  quicklink / system / script execution, window manager, hotkey center and Hyper key.
- `Sources/SopranoCast/Launcher/` — `LauncherController` (state, input, actions) and
  `LauncherWindow` (panel, search bar, list, footer, overlays, HUD).
- `Sources/SopranoCast/App/`, `Shell/` — `main.swift`, app delegate (composition root),
  menu bar, login item, settings and theme centers, app state store, permissions window,
  CLI server/client.
- `Sources/SopranoCast/Settings/` — the settings window (General, Extensions, Advanced):
  reads and writes settings.json only through `SettingsWindowEnvironment`, records hotkeys
  with the launcher's `HotkeyRecordingSession` and recorder card.
- `Sources/SopranoCast/Fixtures/` — fake catalog, runner, hotkeys and the `snapshot`
  harness.
- `Sources/SopranoCast/Vendored/`, `Sources/SopranoCastCore/Vendored/` — Soprano chrome
  and `JSONCText`, synced from Soprano.

## Conventions

- Chrome comes from Soprano: square corners, `ThemeColors` tokens only, Departure Mono via
  `RetroFont.display` at 11 or 22 pt only (small caps; never uppercase strings by hand),
  `RetroFont.body` for running text, `RetroLamp` the only round chrome. Appearance is
  forced dark.
- Core is AppKit-free and everything in it is `public`.
- `System/` is the only place that touches AX, Carbon hotkeys, `CGEventTap`, `hidutil`,
  Apple events or private symbols. The launcher talks to it only through the protocols in
  `System/SystemContracts.swift`, and the shell to the launcher only through
  `Launcher/LauncherContracts.swift`. Contract files change only together with every
  consumer.
- Settings live only in `~/.config/soprano-cast/settings.json`
  (`$XDG_CONFIG_HOME/soprano-cast/` when set; `SOPRANO_CAST_CONFIG` overrides the path).
  A new setting needs its type in `Settings.swift`, the resolver, the template, a control
  in the settings window, the README settings section, and a changelog line. App state
  (usage records, search history) lives in `UserDefaults` under `castUsage` /
  `castHistory`, injected so tests never touch the user's defaults; the only other key is
  `didRequestPermissions` (first-launch prompt, in `UserDefaults.standard`).
- Tests: swift-testing, one `struct …Tests` per file, sentence-style names. Test files
  `import AppKit`, never `Foundation` (the `_Testing_Foundation` overlay breaks the build).
  Tests never touch real settings, real apps, hotkeys, the keychain or the user's defaults:
  settings tests inject the file URL, launcher tests use the fixtures, system tests cover
  only the pure parts.

## Gotchas

- `Sources/SopranoCast/Vendored/` and `Sources/SopranoCastCore/Vendored/JSONCText.swift`
  are copied from Soprano by `scripts/sync-soprano-chrome.sh` (committed Soprano state
  only; source commit in `Vendored/SOPRANO_COMMIT`). Never edit them here: change Soprano,
  commit there, re-run the script. `JSONCText` sits in Core because the settings resolver
  and editor need it. Known upstream bug: its `removing` of an object's last member also
  drops a trailing comment on the line before; fix it in Soprano.
- `SopranoResources` (App/) keeps Soprano's name so vendored files compile unchanged; the
  SPM resource bundle is `SopranoCast_SopranoCast.bundle`.
- TCC grants (Accessibility, Automation) are tied to the signing identity. Sign with the
  shared "Soprano Local Development" identity (`scripts/sign-app.sh`,
  `scripts/ensure-local-signing-identity.sh`), or macOS forgets the permissions on every
  rebuild.
- Two hotkey paths. Combos without `fn` use Carbon `RegisterEventHotKey`: no permission
  needed, they fire while the launcher is key. Named and physical (`key:`) keys register
  their key code; character keys are re-resolved on every input-source change.
  Modifier-only hotkeys (taps, double taps, both sides), `fn` combos and the Hyper key use
  a `CGEventTap` and need Accessibility; without it they are reported as hotkey failures in
  the menu, and a 1 s poll re-applies them once it is granted. The recorder calls
  `suspend()` so it receives `⌘1` itself; always pair it with `resume()`.
- Keys: physical keys (`KeySpec.physical`, `key:'`) are Raycast's default and what the
  recorder saves; plain characters are key equivalents on the current layout. macOS sets
  fn on arrows, Home/End, Page Up/Down, Forward Delete and F-keys; `KeyEventConversion`
  strips it, so fn+arrow hotkeys can't be bound. Keep that when touching key events.
- The Hyper key adds a trigger → F18 entry to the user's `hidutil` `UserKeyMapping` (none
  for the `f18` trigger). Quitting restores the original list; a crash leaves the entry
  until logout, and the next start drops stale entries.
- Raycast registers the same hotkeys (`⌘Space` and every migrated one). Only one app gets
  each: the user quits Raycast and removes it from login items before running Soprano
  Cast (and turns off Spotlight's `⌘Space`).
- Empty Trash (Finder) and Toggle System Appearance (System Events) run AppleScript and
  trigger macOS Automation prompts the first time; Restart / Shut Down / Log Out send
  Apple events to loginwindow (`aevt/rest`, `shut`, `rlgo`).
- Dev (`com.soprano.cast.dev`) and installed (`com.soprano.cast`) apps are separate TCC
  entries and keep separate state.
- The CLI talks to the running app over CFMessagePort `<bundle id>.cli`, so the dev app's
  CLI only reaches the dev app and the installed CLI only the installed app. The bare
  `.build/debug/SopranoCast` has no bundle id and falls back to `com.soprano.cast.cli`, so
  it reaches the installed app.
- Private symbols (`SACLockScreenImmediate`, `_AXUIElementGetWindow`) go through `dlsym`
  and may vanish in a macOS update; every caller handles the nil path.
