# Changelog

All notable changes to Soprano Cast are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Launcher in the Mission Control chrome, opened and closed with `⌘Space` (`launcher.hotkey`), on the display with the mouse, the active window or the primary display (`launcher.screen`); clicking another app closes it (`launcher.closeOnFocusLoss`), and reopening within `launcher.popToRootSeconds` (90 s) keeps the search as you left it.
- Root Search over apps, system commands, window management, quicklinks, script commands and Soprano Cast's own commands, with fuzzy, accent-insensitive matching and highlighted matches; favorites and suggestions (by frecency) when the field is empty, results and `use “<query>” with…` fallbacks (`fallbacks`, Search Google by default) with a query; rows labeled Application, Command, Quicklink or Script Command.
- Inline calculator: `+ - * / × ÷ ^`, percent (`50%`), parentheses, `sqrt`, `round`, `sin`, `log` and more, `pi` and `e`; `↵` copies the answer.
- Aliases per item (`aliases`, Set Alias…) that rank it first and jump to its first argument after a space; favorites (`favorites`, `⌘F`, reordered with `⇧⌘↑` / `⇧⌘↓`); disabling items (`disabled`, `⇧⌘D`).
- Raycast's launcher keys: `↵` / `⌘↵` / `⌥↵` primary, secondary and tertiary actions, `⌘K` Action Panel, `⇧⌘,` Configure Command, `⌘,` settings, `⌃N`/`⌃P` or `⌃J`/`⌃K` (`launcher.navigation`), `⌥↑`/`⌥↓` page, `⌘↑`/`⌘↓` section, `⇥` arguments, `⎋` back, `⌘⎋` pop to root, `⌘W` close, `↑`/`↓` search history.
- Action Panel with Open (`⌘O`), Show in Finder (`⇧⌘O`), Copy Path / Link (`⇧⌘C`), Copy Bundle Identifier / Name (`⌥⌘C`), Quit and Hide Application, Edit Script (`⌘E`), favorites, Set Hotkey… / Remove Hotkey, Set Alias… / Remove Alias and Disable Command, filtered as you type; "Are you sure?" before Restart, Shut Down, Log Out, Empty Trash, Quit All Applications and confirming scripts.
- Global hotkeys on any item, in every Raycast shape: modifier combos (`cmd+key:1`), F13–F20 alone, Hyper combos (`hyper+1`), modifier taps (`rcmd`), double taps (`double:cmd`) and both sides (`both:cmd`), set in `hotkeys` or recorded with Set Hotkey… and conflict warnings ("Used by …"); failures are listed in the menu.
- Hotkeys by key position (`key:'`, `key:§`, `key:0x27`), Raycast's default and what the recorder saves, so they survive switching between keyboard layouts (ABC ↔ German); a plain character (`cmd+'`) follows the current layout instead. Keycaps show what your layout types on the key.
- Hyper key (`hyperKey`): Caps Lock, a right-hand modifier or F18 becomes `⌃⌥⇧⌘` (or `⌃⌥⌘`), with an optional quick press for Caps Lock or Escape; your own `hidutil` key mappings are kept and restored on quit.
- System commands: Lock Screen, Sleep, Sleep Displays, Restart, Shut Down, Log Out, Empty Trash, Eject All Disks, Toggle System Appearance, Quit All Applications, Hide All Apps Except Frontmost, Toggle Hidden Files.
- Window management: fullscreen, maximize, almost maximize, halves, thirds, fourths, quarters, sixths, center, move to an edge (centered along it), make larger / smaller, reasonable size, restore and previous / next display (keeping the aspect ratio), with `windowManagement.gap` and `windowManagement.halves` (stay, cycle sizes, move to display).
- Quicklinks (`quicklinks`) with `{argument}` placeholders, defaults, `{clipboard}`, `{date}`, `{time}`, `{uuid}` and `openWith`.
- Raycast-format script commands from `scriptDirectories` in silent, compact, full-output and inline modes, with up to three text, password or dropdown arguments and confirmation; folders reload when they change.
- `~/.config/soprano-cast/settings.json` (or `$XDG_CONFIG_HOME/soprano-cast/`, or `SOPRANO_CAST_CONFIG`) with live reload; bad values keep their default and show as "settings.json: N warnings" in the menu.
- Menu bar item with Open Soprano Cast, Settings… (`⌘,`), warnings, hotkeys that need attention, Permissions…, Launch at Login (on by default, `app.startAtLogin`) and `app.showMenuBarIcon`.
- Permissions window for Accessibility, needed for window management, modifier-only hotkeys and the Hyper key; waiting hotkeys start as soon as it is granted.
- Command line: `SopranoCast toggle`, `open <item-id> [argument…]`, `list` and `help`.
