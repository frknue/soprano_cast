# Soprano Cast

**A keyboard launcher for macOS, in the Soprano family.**

Soprano Cast is a copy of [Raycast](https://www.raycast.com)'s Root Search and hotkeys in
Soprano's Folio chrome (Folio Paper or Folio Ink): `⌘Space` opens a search over your apps, system
commands, window management, System Settings panes, quicklinks and script commands, with an
inline calculator.
Any of them can get a global hotkey of every kind Raycast offers (`⌘1` for Google Chrome,
a tap of right `⌘`, a double `⇧`, a Hyper key), an alias, or a place in Favorites. It lives
in the menu bar and has no Dock icon. Behavior follows Raycast's manual; no Raycast code is
used.

## Install

```bash
./scripts/install.sh        # release build → /Applications/Soprano Cast.app
```

The installer never restarts a running Soprano Cast; the update applies on the next
launch. Launch at login is on by default. The icon in the menu bar (a search field with a
lens and a caret) means it is running.

The first launch asks macOS once for Accessibility and opens the permissions window while
it is missing. Combo hotkeys like `⌘1` for apps, quicklinks and scripts work without it;
window management, modifier-only and `fn` hotkeys and the Hyper key need it (see
[Permissions](#permissions)).

## The first minutes

1. Press `⌘Space`: the launcher opens on the display with the mouse.
2. Type a few letters of what you want, e.g. `chr` for Google Chrome. Matching is fuzzy.
3. `↵` opens the selected row and closes the launcher. `⎋` closes it without running
   anything.
4. `⌘K` opens the Action Panel for the selected row: everything you can do with it.
5. `⇧⌘,` (Configure Command) sets a hotkey or an alias for the selected row. Choose
   "Set Hotkey…", press the keys (e.g. `⌘1`), and it saves after 1.5 s.
6. `⌘F` adds the selected row to Favorites, shown first when the search field is empty.

## Switching from Raycast

Raycast and Soprano Cast register the same hotkeys (`⌘Space`, and every hotkey you move
over), so only one of them gets each. Quit Raycast, and remove it from your login items
(System Settings → General → Login Items), before starting Soprano Cast. Turn off
Spotlight's `⌘Space` too (System Settings → Keyboard → Keyboard Shortcuts → Spotlight) if it
is still on.

Then set your hotkeys again: in Settings (`⌘,`) → Extensions, click a command's hotkey and
press the keys; or select the item in the launcher, `⇧⌘,` → Set Hotkey…; or write them
under `hotkeys` in settings.json. Aliases and favorites work the same way. There is no
importer for Raycast's export yet.

## Root Search

**Sections.** With an empty search field: **Favorites** (in your order) and
**Suggestions** (up to 6 items you use most, by frecency; favorites excluded, only items
used at least once). With a query: **Calculator** (when the query is a calculation),
**Results** (up to 60), and the fallbacks at the end under `Use “<query>” with…`
(`fallbacks`, by default Search Google), each showing your query. Empty sections are
hidden. "No results" shows when nothing matches, "Type to search apps and commands" when
there is nothing to suggest.

**Rows.** Each row shows its icon, title (matched letters highlighted), subtitle (an app's
folder, a quicklink's link, "System", "Window Management" or "System Settings"), an alias
badge, and at the right its type: Application, Command (system, window, System Settings and
Soprano Cast commands), Quicklink, Script Command (or the script's package name), or the
calculator's expression. The selected row also shows its hotkey.

**Matching and ranking.** Fuzzy, case- and accent-insensitive; several words must all
match; consecutive letters and word starts score higher. An alias equal to the query ranks
first, an alias starting with the query next, then title matches (keywords and subtitle
count half). Within a tier, frecency (how often and how recently you ran it) and favorites
(a small bonus) decide. Disabled items never appear.

**Aliases.** A short name for an item (`gc` for Google Chrome): lowercase letters, digits
and spaces. Typing the alias ranks the item first and shows the alias as a badge; typing
the alias plus a space on an item with arguments selects it and jumps to its first
argument.

**Calculator.** Type an expression: `+ - * / × ÷ ^`, a trailing `%` (percent: `50%` is
0.5), parentheses, unary minus, decimals with `.` or your locale's decimal separator,
`sqrt abs round floor ceil sin cos tan log ln exp` with parentheses (`log` is base 10,
angles in radians), constants `pi` `π` `e`. `^` binds tightest and groups from the right
(`2^3^2` = 512). The answer shows as the first row, formatted for your locale; its only
action is Copy Answer (`↵`). Division by zero and other invalid results show nothing.

**Fallbacks.** Running a fallback row passes the query as its first argument, so Search
Google searches for what you typed. Set them with `fallbacks`.

**Arguments.** Quicklinks and script commands with arguments show argument fields inline
in the search bar (up to 3; text, password or dropdown). `⇥` / `⇧⇥` move between the
query and the fields; `↵` on an item whose required fields are empty focuses the first
empty one ("Fill in <name>" when it already has focus). Values stay while the selection
does.

**History.** `↑` on the first row (or an empty list) puts the previous search back in the
field, `↓` on the last row the next one (past the newest, what you had typed); typing
leaves the history. The last 50 searches you ran something from are kept.

**Closing and reopening.** Running something closes the launcher, and the next opening
starts from Root Search, like Raycast. After `⎋`, `⌘W` or clicking away, reopening within
`launcher.popToRootSeconds` (90 s) shows the search, selection and arguments as you left
them; later it starts fresh. `⌘⎋` clears it right away.

## Launcher shortcuts

| Keys | Action |
|---|---|
| `↑` / `↓` | Previous / next row (history at the top / bottom) |
| `⌃P` / `⌃N` | Previous / next row (`launcher.navigation`: `emacs`, `both`) |
| `⌃K` / `⌃J` | Previous / next row (`launcher.navigation`: `vim`, `both`) |
| `⌥↑` / `⌥↓` | Page up / down |
| `⌘↑` / `⌘↓` | Previous / next section |
| `↵` | Primary action (Open Application, Open Quicklink, Run Script, Run Command, Open System Settings, Copy Answer) |
| `⌘↵` | Secondary action (apps: Show in Finder; quicklinks: Copy Link; scripts: Edit Script) |
| `⌥↵` | Tertiary action (apps: Copy Path) |
| `⌘K` | Action Panel |
| `⇧⌘,` | Configure Command (hotkey and alias) |
| `⌘,` | Settings window |
| `⌘F` | Add to / remove from Favorites |
| `⇧⌘↑` / `⇧⌘↓` | Move favorite up / down |
| `⇧⌘D` | Disable command (hides it from Root Search) |
| `⇥` / `⇧⇥` | Next / previous argument field (items with arguments) |
| `⎋` | Close the top overlay, else close the launcher |
| `⌘⎋` | Pop to root: clear the search, arguments and overlays |
| `⌘W` | Close the launcher |

The Action Panel shortcuts below (`⌘O`, `⇧⌘O`, `⇧⌘C`, `⌥⌘C`, `⌘E`) also work straight
from the list. Everything else (typing, `⌃F`/`⌃B`, `⌘A`/`⌘C`/`⌘V`, `←`/`→`) edits the
search field. Holding `↓` scrolls, but holding `↵` never runs twice. A click selects a
row and a double click runs it. With `launcher.closeOnFocusLoss` on, clicking another app
closes the launcher.

## Action Panel

`⌘K` lists what the selected row can do, in this order (only those that apply):

| Action | Shortcut | For |
|---|---|---|
| Open Application / Open Quicklink / Run Script / Run Command / Open System Settings / Copy Answer | `↵` (also `⌘O`) | everything |
| Show in Finder / Copy Link / Edit Script (the secondary action) | `⌘↵` | apps / quicklinks / scripts |
| Show in Finder | `⇧⌘O` | scripts (apps have it as `⌘↵`) |
| Copy Path | `⇧⌘C` | apps, scripts |
| Copy Bundle Identifier | `⌥⌘C` | apps |
| Copy Name | `⌥⌘C` | everything else |
| Quit Application, Hide Application | — | running apps |
| Add to Favorites / Remove from Favorites | `⌘F` | |
| Move Up in Favorites / Move Down in Favorites | `⇧⌘↑` / `⇧⌘↓` | favorites not already first / last |
| Set Hotkey… | — | |
| Remove Hotkey | — | when one is set |
| Set Alias… | — | |
| Remove Alias | — | when one is set |
| Disable Command | `⇧⌘D` | |

The calculator row has only Copy Answer. Destructive actions (Quit Application, Remove
from Favorites, Remove Hotkey, Remove Alias, Disable Command) are drawn in red. Type to
filter the actions, `↑`/`↓` (and the navigation keys) to move, `↵` to run the selected
action, `⌘↵` the secondary action, `⌘K` or `⎋` to close. `⇧⌘,` opens just the Configure
Command part: Set Hotkey…, Remove Hotkey, Set Alias…, Remove Alias.

Copy Link copies the quicklink's link as written in settings.json, placeholders included.

System Settings panes have Open System Settings and Copy Name besides the favorite, hotkey,
alias and disable entries; no path, Finder or bundle id actions.

**Set Alias…** opens a field prefilled with the current alias; it lowercases as you type,
shows "Use only a–z, 0–9 and spaces" for anything else, and `↵` saves (an empty alias
removes it).

**Confirmation.** Restart, Shut Down, Log Out, Empty Trash, Quit All Applications and
script commands with `needsConfirmation` ask "Are you sure?" first, also when run from a
hotkey: `↵` (the button with the command's name) confirms, `⎋` cancels.

## Hotkeys

Every item (app, system command, window command, System Settings pane, quicklink, script
command, Soprano Cast command) can have a global hotkey. It runs the item without showing
the launcher; an item whose required arguments are empty, or that asks for confirmation,
opens the launcher on it instead. Window commands act on the frontmost window.

| Shape | settings.json | Keycaps |
|---|---|---|
| Modifiers + key | `"cmd+key:1"`, `"cmd+shift+k"`, `"ctrl+opt+left"`, `"fn+a"` | `⌘` `1` |
| Function key alone (F13–F20) | `"f13"` | `F13` |
| Hyper + key | `"hyper+1"`, `"hyper+key:k"` | `✦` `1` |
| Modifier tap | `"rcmd"`, `"lopt"`, `"fn"`, `"cmd+opt"` (several held, then released) | `R⌘` |
| Double tap | `"double:cmd"`, `"double:rshift"` | `⌘` `⌘` |
| Both sides | `"both:cmd"` (not `fn`) | `L⌘` `R⌘` |

**Keys by position or by character.** A printable key can be named two ways:

- **By position**, `key:<name>`: the key at that place on a US keyboard, whatever your
  current layout types there. `cmd+key:'` is the key right of L on every layout, so it
  keeps working when you switch between ABC and German (where it types `ä`). Names: `a`–`z`,
  `0`–`9`, `-` `=` `[` `]` `\` `;` `'` `,` `.` `/` `` ` `` and `§` (the ISO key above Tab),
  or a key code like `key:0x27`. This is Raycast's default, and what the recorder saves:
  recording `⌘1` writes `cmd+key:1`.
- **By character**, the character itself (`cmd+'`, `cmd+k`): the key that types that
  character on your current layout, looked up again whenever the layout changes.

Keycaps show what your current layout types on the key (`⌘` `Ä` for `cmd+key:'` on
German), modifiers in the order `⌃⌥⇧⌘`: `⇧⌘K`.

- Modifiers: `cmd`/`command`/`⌘`, `opt`/`option`/`alt`/`⌥`, `ctrl`/`control`/`⌃`,
  `shift`/`⇧`, `fn`/`function`, joined with `+`; case and spaces don't matter; each at
  most once. Sided names for taps: `l` or `r` before any of them (`lcmd rcmd lopt ropt
  ralt lctrl rctrl lshift rshift`); plain names match either side; `fn` has no sides.
  Combos take plain names only.
- Named keys: `tab`, `space`, `return`, `escape`, `delete`, `forwardDelete`, `left`,
  `right`, `up`, `down`, `home`, `end`, `pageUp`, `pageDown`, `f1`…`f20`; aliases `enter`,
  `esc`, `backspace`, `spacebar`. `cmd++` is `⌘` and the plus key.
- A combo without a modifier is only allowed for F13–F20. `fn` with an arrow, Home/End,
  Page Up/Down, Forward Delete or an F-key can't be bound (macOS sets `fn` on those keys
  by itself). A tap fires when exactly its modifiers go down and up within 0.5 s with no
  other key; a double tap needs the second press within 0.35 s of the first release.

**Apps toggle.** An app's hotkey brings the app to the front; pressed again while that app
is in front with a window on screen, it hides the app, as in Raycast. A frontmost app
without windows (Finder on the desktop) gets a new window instead.

**Recording.** Set Hotkey… (in `⌘K` or `⇧⌘,`) opens the recorder, showing the current
hotkey or "Recording…". Press the combo, tap the modifier(s), tap one twice, or hold both
sides; the keycaps show what was recorded, and it saves after 1.5 s. `↵` saves now, `⌫`
removes the hotkey, `⎋` cancels. Holding `⌃⌥⇧⌘` records those four modifiers, not
`hyper`; write `hyper+…` in settings.json for Hyper hotkeys. While recording, every other
hotkey is paused, so `⌘1` reaches the recorder (and `⌘W` / `⌘⎋` record like any combo).

**Conflicts.** The recorder shows "Used by <title>" in red when another item has the same
hotkey (or one that can't coexist with it: a `⌥` tap with a `⌥⌥` double tap, an any-side
`⌘` tap with both-sided `⌘`); saving takes the hotkey over and removes it from the other
item. The launcher's own hotkey shows "Used by Soprano Cast" and can't be taken. In
settings.json, of two items with the same hotkey (Hyper expanded) the later one (by item
id) is dropped with a warning, and anything clashing with `launcher.hotkey` is dropped.
Hotkeys that fail show as "N hotkeys need attention" in the menu, with the reason in its
tooltip: "already registered" (another app has it), "used by macOS" (an enabled macOS
shortcut; it works once you turn that off), "no key types <c> on this layout", "needs
Accessibility".

**Hyper key.** `hyperKey.trigger` turns a key into Hyper: `capsLock`, `rightCommand`,
`rightOption`, `rightControl`, `rightShift` or `f18` (a key that already sends F18). While
it is held, every key gets `⌃⌥⇧⌘` (`⌃⌥⌘` with `includeShift: false`), so `hyper+…`
hotkeys fire. With the Caps Lock trigger, `quickPress` decides what tapping it alone does:
`nothing`, `toggleCapsLock` or `escape`. The trigger is remapped to F18 with `hidutil`,
next to any key mappings you already have; quitting Soprano Cast restores your mappings,
and macOS resets them at logout. Needs Accessibility.

## Built-in commands

**System** (`system:<id>`):

| Command | id |
|---|---|
| Lock Screen | `lockScreen` |
| Sleep | `sleep` |
| Sleep Displays | `sleepDisplays` |
| Restart (asks first) | `restart` |
| Shut Down (asks first) | `shutDown` |
| Log Out (asks first) | `logOut` |
| Empty Trash (asks first) | `emptyTrash` |
| Eject All Disks | `ejectAllDisks` |
| Toggle System Appearance | `toggleSystemAppearance` |
| Quit All Applications (asks first; keeps Finder and Soprano Cast) | `quitAllApplications` |
| Hide All Apps Except Frontmost | `hideOtherApplications` |
| Toggle Hidden Files (in Finder; relaunches Finder) | `toggleHiddenFiles` |

**Window Management** (`window:<id>`), on the frontmost window:

| Commands | ids |
|---|---|
| Toggle Fullscreen, Maximize, Almost Maximize (90 %), Maximize Height, Maximize Width | `toggleFullscreen` `maximize` `almostMaximize` `maximizeHeight` `maximizeWidth` |
| Left Half, Right Half, Top Half, Bottom Half, Center Half | `leftHalf` `rightHalf` `topHalf` `bottomHalf` `centerHalf` |
| Center, Reasonable Size (60 %, at most 1025 × 900), Make Larger, Make Smaller, Restore | `center` `reasonableSize` `makeLarger` `makeSmaller` `restore` |
| Move Up, Move Down, Move Left, Move Right | `moveUp` `moveDown` `moveLeft` `moveRight` |
| First Third, First Two Thirds, Center Third, Last Two Thirds, Last Third | `firstThird` `firstTwoThirds` `centerThird` `lastTwoThirds` `lastThird` |
| First Fourth, Second Fourth, Third Fourth, Last Fourth | `firstFourth` `secondFourth` `thirdFourth` `lastFourth` |
| Top Left / Top Right / Bottom Left / Bottom Right Quarter | `topLeftQuarter` `topRightQuarter` `bottomLeftQuarter` `bottomRightQuarter` |
| Top Left / Top Center / Top Right / Bottom Left / Bottom Center / Bottom Right Sixth | `topLeftSixth` `topCenterSixth` `topRightSixth` `bottomLeftSixth` `bottomCenterSixth` `bottomRightSixth` |
| Previous Display, Next Display | `previousDisplay` `nextDisplay` |

- Move Up / Down / Left / Right keep the window's size, push it against that edge and
  center it along the edge.
- Previous / Next Display move the window to the display to the left / right (wrapping
  around), at the same relative position and keeping its aspect ratio; it shrinks when the
  other display is smaller.
- Restore returns the window to its frame before the last command that changed it.
- Make Larger / Smaller grow or shrink by 10 % of the display around the window's center.
- `windowManagement.gap` leaves that many points at the display edges and between regions
  (Almost Maximize and Reasonable Size ignore it).
- `windowManagement.halves` decides what Left / Right Half do on a window that already is
  that half: `stay`, `cycleSizes` (½ → ⅔ → ⅓ → ½) or `moveToDisplay` (on to the opposite
  half of the next display in that direction; on the outermost display it stays).

**Soprano Cast** (`cast:<id>`): Soprano Cast Settings (`openSettings`, opens the settings
window), Reload Script Directories (`reloadScripts`), Search Google
(`searchGoogle`), Search DuckDuckGo (`searchDuckDuckGo`), Quit Soprano Cast (`quit`). The
two search commands take a Query argument.

## System Settings

Like Raycast's System Settings extension, every System Settings pane is its own item
(Bluetooth, Wi‑Fi, Displays, Keyboard, Battery, …), with the subtitle "System Settings".
`↵` opens System Settings on that pane. Panes take aliases, hotkeys, favorites and can be
disabled like any command; Settings → Extensions lists them under System Settings.

- The list comes from the System Settings extensions in
  `/System/Library/ExtensionKit/Extensions` that allow opening by URL; they open through
  `x-apple.systempreferences:<bundle id>`. It is read once at launch.
- A pane the extension itself hides on this Mac stays hidden: each extension declares when
  it shows (and under which name), and Soprano Cast evaluates that for a battery, Touch ID,
  a guest user and an optical drive (so a desktop Mac lists Energy, a laptop Battery). A
  pane that depends on a setting (Game Controllers, Class Progress) shows only once that
  setting is on, as in System Settings; a pane whose condition depends on other hardware
  (a mouse, a trackpad) is listed.
- Third-party panes (`*.prefPane` in `/Library/PreferencePanes` and
  `~/Library/PreferencePanes`) are listed too and open as files.
- Titles are in your preferred language; the English name is also searchable, and
  `wi-fi` finds Wi‑Fi (whose title uses a non-breaking hyphen).
- Panes inside a pane (Keyboard Shortcuts, Zoom, …) are not items.

## Quicklinks

A quicklink opens a URL, file, folder or deeplink, filled in from arguments:

```jsonc
"quicklinks": [
  { "id": "github", "name": "GitHub Repo", "link": "https://github.com/{argument name=\"repo\"}", "openWith": "com.google.Chrome", "icon": "🐙" },
  { "id": "dict", "name": "Dictionary", "link": "https://www.dict.cc/?s={argument default=\"hello\"}" },
  { "id": "downloads", "name": "Downloads", "link": "~/Downloads" }
]
```

- `id` (`[a-z0-9-]`, unique; the item id is `quicklink:<id>`), `name` and `link` are
  required; `openWith` is a bundle id, app name or app path (default: the system's choice);
  `icon` an emoji or an image path starting with `/` or `~`.
- Placeholders: `{argument name="x"}` (one argument field per name, at most 3; add
  `default="y"` to make it optional), `{argument}` (named "Query"), legacy `{Query}` /
  `{query}`, `{clipboard}`, `{date}` (yyyy-MM-dd), `{time}` (HH:mm), `{uuid}`. Attributes
  take single or double quotes in any order; anything else in braces stays as written.
- When the link has a URL scheme, every value is percent-encoded like JavaScript's
  `encodeURIComponent` (only letters, digits and `- _ . ! ~ * ' ( )` stay); in file paths
  values go in raw. `~` or a leading `~/` is your home folder. A file link must exist.

## Script commands

Soprano Cast runs [Raycast script commands](https://github.com/raycast/script-commands)
unchanged. Put scripts in a folder listed in `scriptDirectories` (files directly in it and
one level of subfolders; hidden files and names containing `.template.` are skipped).
Folders are watched; Reload Script Directories rescans them and reruns inline scripts.

```bash
#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Say Hello
# @raycast.mode compact
# @raycast.packageName Greetings
# @raycast.icon 👋
# @raycast.argument1 { "type": "text", "placeholder": "Name" }
# @raycast.argument2 { "type": "dropdown", "placeholder": "Tone", "optional": true, "data": [{ "title": "Loud", "value": "loud" }] }
# @raycast.needsConfirmation false

echo "Hello, $1"
```

- Required: `schemaVersion` (1), `title`, `mode`. Optional: `packageName` (shown at the
  right of the row; default the folder name, or the subfolder's), `icon` (emoji, `https`
  URL, or a path relative to the script), `currentDirectoryPath` (default the script's
  folder), `needsConfirmation` (`true` or `false`), `refreshTime` (`10s`, `1m`, `12h`,
  `1d`; at least 10 s), `argument1`…`argument3` (`type` `text`, `password` or
  `dropdown`, `placeholder`, `optional`, `percentEncoded`, `data` for dropdowns),
  `description` (also searched). `iconDark` is ignored. Comments may start with `#`, `//`
  or `--`.
- Modes: `silent` shows the last output line (or the title) in a HUD and closes the
  launcher; `compact` shows the last line in the footer; `fullOutput` shows all output
  (ANSI colors stripped) in the launcher; `inline` shows the last line as the row's
  subtitle, run on load and every `refreshTime` (the first 10 inline scripts), and in the
  footer when run by hand. A non-zero exit shows the last line (or "Script failed") as an
  error.
- Arguments are passed positionally (`$1`, `$2`, `$3`). Scripts run directly when
  executable, else with their shebang interpreter; `PATH` starts with
  `/opt/homebrew/bin:/usr/local/bin`; stdout and stderr are shown together.
- Edit Script (`⌘↵`, `⌘E`) opens the script in its default app, or your text editor when
  that app is a terminal.

## Settings

Settings live in `~/.config/soprano-cast/settings.json` (`$XDG_CONFIG_HOME/soprano-cast/`
when `XDG_CONFIG_HOME` is set; `SOPRANO_CAST_CONFIG` overrides the whole path). The file
is created with comments on first launch, accepts comments and trailing commas, may be a
symlink (a dotfiles link survives), and reloads as soon as you save it. Every key is
optional; the settings window and the Action Panel edit the same file and keep your
comments and key order.

### Settings window

`⌘,` in the launcher, Settings… in the menu, or the Soprano Cast Settings command opens it,
laid out like Raycast's Settings. Every control writes settings.json; edits you make in the
file show up in the window at once.

- **General**: the settings.json card (its warnings, Open settings.json, Reveal in Finder),
  Launch at login, the Soprano Cast hotkey, Show in menu bar, Theme, and your Favorites and
  Fallback Commands in order (↑ ↓ to reorder, ✕ to remove).
- **Extensions**: every command grouped like Raycast's table (Applications, Quicklinks,
  Script Commands, Soprano Cast, System, System Settings, Window Management) with its type,
  alias, hotkey and Enabled box (off hides it from Root Search; its hotkey still works),
  and a search field. Click a hotkey to record it in the same recorder as Set Hotkey…
  (`↵` saves now, `⌫` removes, `⎋` cancels; a hotkey another command holds moves over to
  this one). The pane on the right shows the selected command (alias, hotkey, Show in Root
  Search, Favorite, Fallback command, and a quicklink's name, link, open-with app and icon with
  Save and Delete Quicklink) or group: application folders, script folders, Create
  Quicklink, and Window Management's gap and cycling.
- **Advanced**: Show Soprano Cast on, Pop to Root Search, navigation bindings, closing when
  another app is clicked, and the Hyper key (key, include ⇧, quick press).

A bad value is ignored and keeps its default; it never stops the app. The menu shows
"settings.json: N warnings" with every message in its tooltip, for example:

```text
line 12: windowManagement.halves: "cycle" is not one of "stay", "cycleSizes", "moveToDisplay"; kept "stay".
```

A file that is not valid JSON keeps the last good settings running.

```jsonc
{
  // "soprano" follows Soprano's theme and appearance; "folio" (Paper or Ink) follows the
  // system appearance; or a pinned theme: folio-paper, folio-ink, gruvbox-dark,
  // catppuccin-mocha, dracula, solarized-dark, nord, tokyo-night, atom-one-dark.
  "theme": "soprano",

  "launcher": {
    "hotkey": "cmd+space",          // any hotkey shape (see Hotkeys); null = none
    "screen": "withMouse",          // withMouse, withActiveWindow, primary
    "popToRootSeconds": 90,         // 0–3600; reopening later starts fresh
    "navigation": "emacs",          // emacs (⌃N/⌃P), vim (⌃J/⌃K), both
    "closeOnFocusLoss": true        // clicking another app closes the launcher
  },

  // Global hotkeys per item id; null removes one.
  "hotkeys": {
    "app:com.google.Chrome": "cmd+key:1",
    "window:leftHalf": "ctrl+opt+left",
    "system:lockScreen": "double:rcmd"
  },

  // Root Search aliases: lowercase a–z, 0–9 and spaces.
  "aliases": { "app:com.google.Chrome": "gc" },

  // The Favorites section, in order.
  "favorites": ["app:com.google.Chrome"],

  // Hidden from Root Search; their hotkeys still work.
  "disabled": ["system:toggleHiddenFiles"],

  // Offered after the results for any query.
  "fallbacks": ["cast:searchGoogle"],

  "quicklinks": [
    { "id": "github", "name": "GitHub Repo", "link": "https://github.com/{argument name=\"repo\"}", "openWith": "com.google.Chrome", "icon": "🐙" }
  ],

  // Folders of Raycast-format script commands (~ allowed).
  "scriptDirectories": ["~/raycast-scripts"],

  // Extra folders searched for applications.
  "applicationDirectories": [],

  "hyperKey": {
    "trigger": null,                // null, capsLock, rightCommand, rightOption, rightControl, rightShift, f18
    "includeShift": true,           // Hyper = ⌃⌥⇧⌘ (false: ⌃⌥⌘)
    "quickPress": "nothing"         // nothing, toggleCapsLock, escape (capsLock trigger only)
  },

  "windowManagement": {
    "gap": 0,                       // 0–64 points
    "halves": "stay"                // stay, cycleSizes, moveToDisplay
  },

  "app": {
    "startAtLogin": true,
    "showMenuBarIcon": true
  }
}
```

The file written on first launch has empty `hotkeys`, `aliases`, `favorites`, `disabled`,
`quicklinks` and `scriptDirectories`; the values above are examples.

Item ids:

| Kind | id |
|---|---|
| App | `app:<bundle id>` (`app:<path>` for apps without one) |
| System command | `system:<id>` (see Built-in commands) |
| Window command | `window:<id>` |
| Soprano Cast command | `cast:<id>` |
| Quicklink | `quicklink:<id>` |
| Script command | `script:<absolute path>` |
| System Settings pane | `pane:<bundle id>` (e.g. `pane:com.apple.BluetoothSettings`; `pane:<path>` for a third-party `.prefPane` without one) |

`SopranoCast list` prints every id. Notes:

- An id with an unknown prefix or nothing after the colon is dropped with a warning. Ids
  of items that don't exist right now (an app not installed yet) are kept.
- An invalid hotkey is dropped with a warning. Two hotkeys with the same shape (Hyper
  expanded): the later item id is dropped with a warning naming both; a hotkey equal to
  `launcher.hotkey` is dropped with a warning.
- Aliases are trimmed and lowercased. An empty alias or one with other characters than
  a–z, 0–9 and space is dropped; duplicate aliases warn but both stay.
- An entry listed twice in `favorites`, `disabled` or `fallbacks` is dropped; a value that
  isn't a list keeps the default.
- Quicklinks need a unique `id` matching `[a-z0-9-]+`, a `name` and a `link`; a bad
  `openWith` or `icon` is ignored, and unknown keys inside a quicklink warn.
- `quickPress` other than `nothing` needs `"trigger": "capsLock"`; otherwise it warns and
  stays `nothing`.
- Numbers out of range are clamped with a warning. Booleans must be JSON booleans and whole
  numbers whole.
- Apps are found in /Applications, /System/Applications, ~/Applications,
  /System/Library/CoreServices/Applications (with their subfolders), Finder, and
  `applicationDirectories`.
- With `showMenuBarIcon: false`, open Soprano Cast again from Spotlight or Finder to show
  the launcher; settings are a `⌘,` away there.

## Menu bar

Open Soprano Cast (with the launcher hotkey), Settings… (`⌘,`), "settings.json: N
warnings" while the file has problems, "N hotkeys need attention" while hotkeys or the
Hyper key failed (hover either for the messages), Permissions…, Launch at Login, About
Soprano Cast, and Quit Soprano Cast (`⌘Q`). Hidden with `app.showMenuBarIcon: false`.

## Permissions

The permissions window (first launch while Accessibility is missing, and Permissions… in
the menu) shows Accessibility with a lamp, green when granted and red when missing, and an
Open System Settings button. It updates as soon as you grant it, and hotkeys that were
waiting for it start working without a relaunch.

- **Accessibility**: window management, modifier-only hotkeys (taps, double taps, both
  sides), `fn` hotkeys and the Hyper key. Ordinary combos like `⌘1` and `⌘Space` work
  without it.
- **Automation**: Empty Trash (Finder) and Toggle System Appearance (System Events);
  macOS asks once per target app the first time.

## Command line

The app binary doubles as a command line client for the running app:

```text
Usage: SopranoCast <command>

  toggle                          Open or close the launcher
  open <item-id> [argument…]      Run an item as its hotkey would, e.g. open app:com.google.Chrome
                                  or open cast:searchGoogle "swift testing"
  list                            List every item as JSON, sorted by title
  help                            Show this help
```

```bash
CAST="/Applications/Soprano Cast.app/Contents/MacOS/SopranoCast"
"$CAST" toggle
"$CAST" open app:com.google.Chrome
"$CAST" open quicklink:github soprano-cast
"$CAST" list
```

- `open` runs the item without showing the launcher; arguments fill its argument fields in
  order. An item with required arguments missing (or that asks for confirmation) opens the
  launcher on it. Disabled items still run.
- `list` prints a JSON array with `id`, `title`, `kind` (`application`, `systemCommand`,
  `windowCommand`, `quicklink`, `script`, `castCommand`, `settingsPane`), `subtitle`,
  `hotkey` (as in settings.json) and `alias` when set, `favorite` and `disabled`.
- `help` / `--help` print the usage (exit 0). Malformed arguments print the usage on stderr
  (exit 2). Errors print on stderr with exit 1: "Soprano Cast is not running.", "Soprano
  Cast did not answer.", "Unknown item id <id>; ids look like app:com.google.Chrome",
  "No item <id>".

## Development

```bash
export DEVELOPER_DIR=/Library/Developer/CommandLineTools PATH="/opt/homebrew/opt/swift/bin:$PATH"
swift build
swift test
./scripts/dev.sh                      # build, package and launch Soprano Cast Dev.app
.build/debug/SopranoCast snapshot --out /tmp/cast.png
.build/debug/SopranoCast snapshot --out /tmp/cast.png --query "chr" --keys "cmd+k" --report /tmp/cast.json
.build/debug/SopranoCast snapshot --out /tmp/calc.png --query "2^10 / 4"
.build/debug/SopranoCast snapshot --out /tmp/rec.png --query "chrome" --keys "shift+cmd+, return rec:cmd+1 wait" --report /tmp/rec.json
.build/debug/SopranoCast snapshot --out /tmp/settings.png --settings-window extensions --select app:com.google.Chrome --record app:com.google.Chrome --keys "rec:cmd+2"
```

`DEVELOPER_DIR` pins the Command Line Tools SDK, because Homebrew Swift can't read Xcode's
newer one. `snapshot` renders the real launcher on fixture apps and scripts offscreen,
without hotkeys or permissions. `--keys` replays key tokens (`cmd+k`, `shift+cmd+,`,
`key:'`, `rec:<hotkey>` to record a hotkey, `wait` to let the recorder's countdown or a
toast timer run; time stands still otherwise); `--settings <jsonc>`, `--screen 1512x982`
and `--theme <id>` vary the setup (snapshots draw Folio Paper; `--theme folio-ink` draws
Ink), and `--report` writes the query, rows, selection,
overlay, footer toast, runs and settings edits as JSON. `--settings-window general`,
`extensions` or `advanced` renders the settings window instead (`--select` a row or
`group:<group>`, `--filter` its table, `--record` a hotkey with `--keys`). `snapshot`
without options prints its full usage. The dev app (`com.soprano.cast.dev`) has its own
permissions and state, and its command line only reaches the dev app; the bare
`.build/debug/SopranoCast` reaches the installed app. The design system
(`Sources/SopranoCast/Vendored/`), `JSONCText` and the app icon renderer
(`scripts/render-app-icon.swift`) come from Soprano; update them with
`scripts/sync-soprano-chrome.sh` instead of editing them here. `docs/ARCHITECTURE.md`
describes the modules, and `docs/ROADMAP.md` lists what is not copied.

## License

[MIT](LICENSE).
