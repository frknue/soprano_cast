# Changelog

All notable changes to Soprano Cast are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Launcher in the Mission Control chrome, opened and closed with `⌘Space` (`launcher.hotkey`), on the display with the mouse, the active window or the primary display (`launcher.screen`); clicking another app closes it (`launcher.closeOnFocusLoss`).
- Root Search over apps, system commands, window management, quicklinks, script commands and Soprano Cast's own commands, with fuzzy, accent-insensitive matching and highlighted matches; Favorites and Suggestions (by frecency) when the field is empty, Results and Fallbacks (`fallbacks`, Search Google by default) with a query.
- Inline calculator: `+ - * / × ÷ ^ %`, parentheses, `sqrt`, `round`, `sin`, `log` and more, `pi` and `e`; `↵` copies the answer.
- Aliases per item (`aliases`) that rank it first and jump to its first argument after a space; favorites (`favorites`, `⌘F`, reordered with `⇧⌘↑` / `⇧⌘↓`); disabling items (`disabled`, `⇧⌘D`).
- Raycast's launcher keys: `↵` / `⌘↵` / `⌥↵` primary, secondary and tertiary actions, `⌘K` Action Panel, `⇧⌘,` Configure Command, `⌘,` settings, `⌃N`/`⌃P` or `⌃J`/`⌃K` (`launcher.navigation`), `⌥↑`/`⌥↓` page, `⌘↑`/`⌘↓` section, `⇥` arguments, `⎋` back, `⌘⎋` pop to root, `⌘W` close, `↑`/`↓` search history.
- Action Panel with Open, Show in Finder (`⇧⌘O`), Copy Path / Link / Result (`⇧⌘C`), Copy Bundle Identifier / Name (`⌥⌘C`), Quit and Hide Application, Edit Script (`⌘E`), favorites, hotkey and alias actions, and Disable Command, filtered as you type.
- Global hotkeys on any item, in every Raycast shape: modifier combos (`cmd+1`), F13–F20 alone, Hyper combos (`hyper+1`), modifier taps (`rcmd`), double taps (`double:cmd`) and both sides (`both:cmd`), set in `hotkeys` or recorded from the Action Panel with conflict warnings ("Used by …"); character keys follow the current keyboard layout.
- Hyper key (`hyperKey`): Caps Lock or a right-hand modifier becomes `⌃⌥⇧⌘` (or `⌃⌥⌘`), with an optional quick press for Caps Lock or Escape.
- System commands: Lock Screen, Sleep, Sleep Displays, Restart, Shut Down, Log Out, Empty Trash, Eject All Disks, Toggle System Appearance, Quit All Applications, Hide All Apps Except Frontmost, Toggle Hidden Files; destructive ones ask first.
- Window management: fullscreen, maximize, almost maximize, halves, thirds, fourths, quarters, sixths, center, move, make larger / smaller, reasonable size, restore and previous / next display, with `windowManagement.gap` and `windowManagement.halves` (stay, cycle sizes, move to display).
- Quicklinks (`quicklinks`) with `{argument}` placeholders, defaults, `{clipboard}`, `{date}`, `{time}`, `{uuid}` and `openWith`.
- Raycast-format script commands from `scriptDirectories` in silent, compact, full-output and inline modes, with up to three text, password or dropdown arguments and confirmation; folders reload when they change.
- `~/.config/soprano-cast/settings.json` (or `SOPRANO_CAST_CONFIG`) with live reload; bad values keep their default and show as "settings.json: N warnings" in the menu.
- Menu bar item with Open Soprano Cast, Settings… (`⌘,`), warnings, hotkeys that need attention, Permissions…, Launch at Login (on by default, `app.startAtLogin`) and `app.showMenuBarIcon`.
- Permissions window for Accessibility, needed for window management, modifier-only hotkeys and the Hyper key.
- Command line: `SopranoCast toggle`, `open <item id> [argument…]`, `list` and `help`.
