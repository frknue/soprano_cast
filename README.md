# Soprano Cast

**A keyboard launcher for macOS, in the Soprano family.**

Soprano Cast is a copy of [Raycast](https://www.raycast.com)'s Root Search and hotkeys in
Soprano's "Mission Control" chrome: `⌘Space` opens a search over your apps, system
commands, window management, quicklinks and script commands, with an inline calculator.
Any of them can get a global hotkey of every kind Raycast offers (`⌘1` for Google Chrome,
a tap of right `⌘`, a double `⇧`, a Hyper key), an alias, or a place in Favorites. It lives
in the menu bar and has no Dock icon. Behavior follows Raycast's manual; no Raycast code is
used.

## Install

```bash
./scripts/install.sh        # release build → /Applications/Soprano Cast.app
```

The installer never restarts a running Soprano Cast; the update applies on the next
launch. Launch at login is on by default. The icon in the menu bar (a square with a
slanted beam) means it is running.

The first launch opens the permissions window while Accessibility is missing. App,
quicklink, script and system-command hotkeys work without it; window management,
modifier-only and `fn` hotkeys and the Hyper key need it (see [Permissions](#permissions)).

## The first minutes

1. Press `⌘Space`: the launcher opens on the display with the mouse.
2. Type a few letters of what you want, e.g. `chr` for Google Chrome. Matching is fuzzy.
3. `↵` opens the selected row. `⎋` closes the launcher.
4. `⌘K` opens the Action Panel for the selected row: everything you can do with it.
5. `⇧⌘,` (Configure Command) sets a hotkey or an alias for the selected row. Choose
   "Set Hotkey", press the keys (e.g. `⌘1`), and it saves after 1.5 s.
6. `⌘F` adds the selected row to Favorites, shown first when the search field is empty.

## Switching from Raycast

Raycast holds `⌘Space` while it runs, so Soprano Cast's launcher hotkey can't fire until
you either quit Raycast or clear Raycast's hotkey (Raycast Settings → General → Raycast
Hotkey). Turn off Spotlight's `⌘Space` too (System Settings → Keyboard → Keyboard
Shortcuts → Spotlight) if it is still on. Your other Raycast hotkeys also clash while
Raycast runs. Hotkeys, aliases and favorites are set in Soprano Cast's own settings.json
or from the Action Panel.

## Root Search

**Sections.** With an empty search field: **Favorites** (in your order) and
**Suggestions** (up to 6 items you use most, by frecency; favorites excluded, only items
used at least once). With a query: **Calculator** (when the query is a calculation),
**Results** (up to 60), and **Fallbacks** (`fallbacks`, by default Search Google) at the
end. Empty sections are hidden. "No results" shows when nothing matches, "Type to search
apps and commands" when there is nothing to suggest.

**Matching and ranking.** Fuzzy, case- and accent-insensitive; several words must all
match; consecutive letters and word starts score higher, and matched letters are
highlighted. An alias equal to the query ranks first, an alias starting with the query
next, then title matches (keywords and subtitle count half). Within a tier, frecency (how
often and how recently you ran it) and favorites (a small bonus) decide. Disabled items
never appear.

**Aliases.** A short name for an item (`gc` for Google Chrome): lowercase letters, digits
and spaces. Typing the alias ranks the item first and shows the alias as a badge; typing
the alias plus a space on an item with arguments jumps to its first argument.

**Calculator.** Type an expression: `+ - * / × ÷ ^ %`, parentheses, unary minus, decimals
with `.` or your locale's decimal separator, `sqrt abs round floor ceil sin cos tan log
ln exp` (`log` is base 10), constants `pi` `π` `e`. The answer shows as the first row;
`↵` copies it (Copy Answer). Division by zero and other invalid results show nothing.

**Fallbacks.** Rows offered after the results for any query ("Use “x” with …"). Running
one passes the query as its first argument, so Search Google searches for what you typed.
Set them with `fallbacks`.

**Arguments.** Quicklinks and script commands with arguments show argument fields inline
in the search bar (up to 3; text, password or dropdown). `⇥` / `⇧⇥` move between the
query and the fields; `↵` on an item whose required fields are empty focuses the first
empty one ("Fill in <name>" when it already has focus). Values stay while the selection
does.

**History.** `↑` on the first row (or an empty list) puts the previous search back in the
field, `↓` on the last row the next one; typing leaves the history. The last 50 searches
you ran something from are kept.

**Pop to root.** Reopening the launcher within `launcher.popToRootSeconds` (90 s) shows
it exactly as you left it; later it starts fresh. `⌘⎋` clears it right away.

## Launcher shortcuts

| Keys | Action |
|---|---|
| `↑` / `↓` | Previous / next row (history at the top / bottom) |
| `⌃P` / `⌃N` | Previous / next row (`launcher.navigation`: `emacs`, `both`) |
| `⌃K` / `⌃J` | Previous / next row (`launcher.navigation`: `vim`, `both`) |
| `⌥↑` / `⌥↓` | Page up / down |
| `⌘↑` / `⌘↓` | Previous / next section |
| `↵` | Primary action (open, run, copy answer) |
| `⌘↵` | Secondary action (Show in Finder, Copy Link, Edit Script, Copy Result) |
| `⌥↵` | Tertiary action (apps: Copy Path) |
| `⌘K` | Action Panel |
| `⇧⌘,` | Configure Command (hotkey and alias) |
| `⌘,` | Open settings.json |
| `⌘F` | Add to / remove from Favorites |
| `⇧⌘↑` / `⇧⌘↓` | Move favorite up / down |
| `⇧⌘D` | Disable command (hides it from Root Search) |
| `⇥` / `⇧⇥` | Next / previous argument field |
| `⎋` | Close the top overlay, else close the launcher |
| `⌘⎋` | Pop to root: clear the search, arguments and overlays |
| `⌘W` | Close the launcher |

The Action Panel shortcuts below also work straight from the list. Everything else
(typing, `⌃F`/`⌃B`, `⌘A`/`⌘C`/`⌘V`, `←`/`→`) edits the search field. With
`closeOnFocusLoss` on, clicking another app closes the launcher.

## Action Panel

`⌘K` lists what the selected row can do, in this order (only those that apply):

| Action | Shortcut | For |
|---|---|---|
| Primary: Open Application / Open Quicklink / Run Script / Run Command / Copy Answer | `↵` (`⌘O`) | everything |
| Secondary | `⌘↵` | see above |
| Show in Finder | `⇧⌘O` | apps, scripts |
| Copy Path / Copy Link / Copy Result | `⇧⌘C` | apps / quicklinks / calculator |
| Copy Bundle Identifier / Copy Name | `⌥⌘C` | apps / other items |
| Quit Application, Hide Application | — | running apps |
| Edit Script | `⌘E` | scripts |
| Add to / Remove from Favorites | `⌘F` | |
| Move Favorite Up / Down | `⇧⌘↑` / `⇧⌘↓` | favorites not already first / last |
| Set Hotkey | — | |
| Remove Hotkey | — | when one is set |
| Set Alias | — | |
| Remove Alias | — | when one is set |
| Disable Command | `⇧⌘D` | |

Type to filter the actions, `↑`/`↓` (and the navigation keys) to move, `↵` to run the
selected action, `⌘↵` the secondary action, `⌘K` or `⎋` to close. `⇧⌘,` opens just the
Configure Command part: Set Hotkey, Remove Hotkey, Set Alias, Remove Alias.

Commands marked for confirmation (Restart, Shut Down, Log Out, Empty Trash, Quit All
Applications, script commands with `needsConfirmation`) ask first: `↵` confirms, `⎋`
cancels.

## Hotkeys

Every item (app, system command, window command, quicklink, script command, Soprano Cast
command) can have a global hotkey. It runs the item without showing the launcher; an item
whose required arguments are empty opens the launcher on it instead. Window commands act
on the frontmost window.

| Shape | settings.json | Keycaps |
|---|---|---|
| Modifiers + key | `"cmd+1"`, `"cmd+shift+k"`, `"ctrl+opt+left"`, `"fn+a"` | `⌘` `1` |
| Function key alone (F13–F20) | `"f13"` | `F13` |
| Hyper + key | `"hyper+1"` | `✦` `1` |
| Modifier tap | `"rcmd"`, `"lopt"`, `"fn"`, `"cmd+opt"` (several held, then released) | `R⌘` |
| Double tap | `"double:cmd"`, `"double:rshift"` | `⌘` `⌘` |
| Both sides | `"both:cmd"` (not `fn`) | `L⌘` `R⌘` |

- Modifiers: `cmd`/`command`/`⌘`, `opt`/`option`/`alt`/`⌥`, `ctrl`/`control`/`⌃`,
  `shift`/`⇧`, `fn`/`function`, joined with `+`; case and spaces don't matter. Sided:
  `lcmd rcmd lopt ropt lctrl rctrl lshift rshift` (plain names match either side).
- Keys: `tab`, `space`, `return`, `escape`, `delete`, `forwardDelete`, `left`, `right`,
  `up`, `down`, `home`, `end`, `pageUp`, `pageDown`, `f1`…`f20`; aliases `enter`, `esc`,
  `backspace`, `spacebar`. Any other single character is the key that types it on your
  current layout, so `cmd+shift+1` is `⌘⇧1`, not `⌘!`.
- A combo without a modifier is only allowed for F13–F20. A tap fires when exactly its
  modifiers go down and up within 0.5 s with no other key; a double tap needs the second
  press within 0.35 s of the first release.

**Recording.** Set Hotkey (in `⌘K` or `⇧⌘,`) opens the recorder. Press the combo, tap the
modifier(s), tap one twice, or hold both sides; the keycaps show what was recorded, and it
saves after 1.5 s. `↵` saves now, `⌫` removes the hotkey, `⎋` cancels. Holding `⌃⌥⇧⌘`
records those four modifiers, not `hyper`; write `hyper+…` in settings.json for Hyper
hotkeys. While recording, every other hotkey is paused, so `⌘1` reaches the recorder.

**Conflicts.** The recorder shows "Used by <title>" in red when another item has the same
hotkey (or one that can't coexist with it: a `⌥` tap with a `⌥⌥` double tap, an any-side
`⌘` tap with both-sided `⌘`); saving takes the hotkey over and removes it from the other
item. The launcher's own hotkey shows "Used by Soprano Cast" and can't be taken. In
settings.json, of two items with the same hotkey the later one (by item id) is dropped with
a warning, and anything clashing with `launcher.hotkey` is dropped. Hotkeys that fail to
register (taken by another app, or needing Accessibility) show as "N hotkeys need
attention" in the menu.

**Hyper key.** `hyperKey.trigger` turns a key into Hyper: `capsLock`, `rightCommand`,
`rightOption`, `rightControl`, `rightShift` or `f18`. While it is held, every key gets
`⌃⌥⇧⌘` (`⌃⌥⌘` with `includeShift: false`), so `hyper+1` hotkeys fire. With the Caps Lock
trigger, `quickPress` decides what tapping it alone does: `nothing`, `toggleCapsLock` or
`escape`. The trigger is remapped with `hidutil`; the mapping is removed when Soprano Cast
quits and resets at logout. Needs Accessibility.

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
| Toggle Hidden Files (in Finder) | `toggleHiddenFiles` |

**Window Management** (`window:<id>`), on the frontmost window:

| Commands | ids |
|---|---|
| Toggle Fullscreen, Maximize, Almost Maximize (90 %), Maximize Height, Maximize Width | `toggleFullscreen` `maximize` `almostMaximize` `maximizeHeight` `maximizeWidth` |
| Left Half, Right Half, Top Half, Bottom Half, Center Half | `leftHalf` `rightHalf` `topHalf` `bottomHalf` `centerHalf` |
| Center, Reasonable Size (60 %, at most 1025 × 900), Make Larger, Make Smaller, Restore | `center` `reasonableSize` `makeLarger` `makeSmaller` `restore` |
| Move Up, Move Down, Move Left, Move Right (to that edge, same size) | `moveUp` `moveDown` `moveLeft` `moveRight` |
| First Third, First Two Thirds, Center Third, Last Two Thirds, Last Third | `firstThird` `firstTwoThirds` `centerThird` `lastTwoThirds` `lastThird` |
| First Fourth, Second Fourth, Third Fourth, Last Fourth | `firstFourth` `secondFourth` `thirdFourth` `lastFourth` |
| Top Left / Top Right / Bottom Left / Bottom Right Quarter | `topLeftQuarter` `topRightQuarter` `bottomLeftQuarter` `bottomRightQuarter` |
| Top Left / Top Center / Top Right / Bottom Left / Bottom Center / Bottom Right Sixth | `topLeftSixth` `topCenterSixth` `topRightSixth` `bottomLeftSixth` `bottomCenterSixth` `bottomRightSixth` |
| Previous Display, Next Display (displays ordered left to right) | `previousDisplay` `nextDisplay` |

Restore returns the window to its frame before the last command. Make Larger / Smaller
grow or shrink by 10 % of the display around the window's center. `windowManagement.gap`
leaves that many points at the display edges and between regions. `windowManagement.halves`
decides what Left / Right Half do on a window that already is that half: `stay`,
`cycleSizes` (½ → ⅔ → ⅓ → ½) or `moveToDisplay` (on to the next display in that
direction).

**Soprano Cast** (`cast:<id>`): Soprano Cast Settings (`openSettings`, opens
settings.json), Reload Script Directories (`reloadScripts`), Search Google
(`searchGoogle`), Search DuckDuckGo (`searchDuckDuckGo`), Quit Soprano Cast (`quit`).

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
  `icon` an emoji or image path.
- Placeholders: `{argument name="x"}` (one argument field per name, at most 3; add
  `default="y"` to make it optional), `{argument}` (named "Query"), legacy `{Query}` /
  `{query}`, `{clipboard}`, `{date}` (yyyy-MM-dd), `{time}` (HH:mm), `{uuid}`.
- Values are percent-encoded when the link has a URL scheme and inserted raw into file
  paths; a leading `~` is your home folder.
- `⌘↵` copies the expanded link instead of opening it.

## Script commands

Soprano Cast runs [Raycast script commands](https://github.com/raycast/script-commands)
unchanged. Put scripts in a folder listed in `scriptDirectories` (files directly in it and
one level of subfolders; names containing `.template.` are skipped). Folders are watched,
or run Reload Script Directories.

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

- Required: `schemaVersion` (1), `title`, `mode`. Optional: `packageName` (shown as the
  subtitle; default the folder name), `icon` (emoji, `https` URL, or a path relative to the
  script), `currentDirectoryPath` (default the script's folder), `needsConfirmation`,
  `refreshTime` (`10s`, `1m`, `12h`, `1d`; at least 10 s), `argument1`…`argument3`
  (`type` `text`, `password` or `dropdown`, `placeholder`, `optional`, `percentEncoded`,
  `data` for dropdowns), `description`. `iconDark` is ignored. Comments may start with `#`
  or `//`.
- Modes: `silent` shows the last output line (or the title) in a HUD and closes the
  launcher; `compact` shows the last line in the footer; `fullOutput` shows all output
  (ANSI colors stripped) in the launcher; `inline` shows the last line as the row's
  subtitle, refreshed every `refreshTime` (the first 10 inline scripts). A non-zero exit
  shows the last line (or "Script failed") as an error.
- Arguments are passed positionally (`$1`, `$2`, `$3`). Scripts run directly when
  executable, else with their shebang interpreter; `PATH` starts with
  `/opt/homebrew/bin:/usr/local/bin`.
- `⌘↵` (Edit Script, `⌘E`) opens the script in its editor.

## Settings

Settings live in `~/.config/soprano-cast/settings.json` (`SOPRANO_CAST_CONFIG` overrides
the path). The file is created with comments on first launch, accepts comments and
trailing commas, and reloads as soon as you save it. Open it with `⌘,` in the launcher, the
menu, or Soprano Cast Settings. Every key is optional; the Action Panel edits the same
file and keeps your comments.

A bad value is ignored and keeps its default; it never stops the app. The menu shows
"settings.json: N warnings" with every message in its tooltip. A file that is not valid
JSON keeps the last good settings running.

```jsonc
{
  // A Soprano theme id, or "soprano" to follow Soprano's own theme setting.
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
    "app:com.google.Chrome": "cmd+1",
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

Item ids:

| Kind | id |
|---|---|
| App | `app:<bundle id>` (`app:<path>` for apps without one) |
| System command | `system:<id>` (see Built-in commands) |
| Window command | `window:<id>` |
| Soprano Cast command | `cast:<id>` |
| Quicklink | `quicklink:<id>` |
| Script command | `script:<absolute path>` |

`SopranoCast list` prints every id. Notes:

- An id with an unknown prefix is dropped with a warning. Ids of items that don't exist
  right now (an app not installed yet) are kept.
- Two hotkeys with the same shape: the later item id is dropped with a warning naming both;
  a hotkey equal to `launcher.hotkey` is dropped.
- An alias with other characters than a–z, 0–9 and space is dropped; duplicate aliases warn
  but both stay.
- Quicklinks need a unique `id` matching `[a-z0-9-]+`, a `name` and a `link`.
- `quickPress` other than `nothing` needs `"trigger": "capsLock"`; otherwise it warns and
  stays `nothing`.
- Numbers out of range are clamped with a warning. Booleans must be JSON booleans and whole
  numbers whole.
- Apps are found in /Applications, /System/Applications (both with Utilities),
  ~/Applications, /System/Library/CoreServices/Applications, Finder's folder, and
  `applicationDirectories`.
- With `showMenuBarIcon: false`, open Soprano Cast again from Spotlight or Finder to show
  the launcher.

## Menu bar

Open Soprano Cast (with the launcher hotkey), Settings… (`⌘,`), "settings.json: N
warnings" while the file has problems, "N hotkeys need attention" while hotkeys failed to
register (hover either for the messages), Permissions…, Launch at Login, About Soprano
Cast, and Quit Soprano Cast (`⌘Q`). Hidden with `app.showMenuBarIcon: false`.

## Permissions

The permissions window (first launch while Accessibility is missing, and Permissions… in
the menu) shows Accessibility with a lamp, green when granted and red when missing, and an
Open System Settings button. It updates as soon as you grant it.

- **Accessibility**: window management, modifier-only hotkeys (taps, double taps, both
  sides), `fn` hotkeys and the Hyper key. Ordinary combos like `⌘1` and `⌘Space` work
  without it.
- **Automation**: Restart, Shut Down, Log Out, Empty Trash and Toggle System Appearance
  send Apple events; macOS asks once per target app the first time.

## Command line

The app binary doubles as a command line client for the running app:

```text
Usage: SopranoCast <command>

  toggle                       Show or hide the launcher
  open <item id> [argument…]   Run an item, as its hotkey would
  list                         List every item as JSON, sorted by title
  help                         Show this help
```

```bash
CAST="/Applications/Soprano Cast.app/Contents/MacOS/SopranoCast"
"$CAST" toggle
"$CAST" open app:com.google.Chrome
"$CAST" open quicklink:github soprano-cast
"$CAST" list
```

`open` runs the item without showing the launcher; an item with required arguments and none
given opens the launcher on it. `help` / `--help` print the usage.

## Development

```bash
export DEVELOPER_DIR=/Library/Developer/CommandLineTools PATH="/opt/homebrew/opt/swift/bin:$PATH"
swift build
swift test
./scripts/dev.sh                      # build, package and launch Soprano Cast Dev.app
.build/debug/SopranoCast snapshot --out /tmp/cast.png
.build/debug/SopranoCast snapshot --out /tmp/cast.png --query "chr" --keys "cmd+k" --report /tmp/cast.json
.build/debug/SopranoCast snapshot --out /tmp/calc.png --query "2^10 / 4"
.build/debug/SopranoCast snapshot --out /tmp/rec.png --query "chrome" --keys "shift+cmd+, return rec:cmd+1"
```

`DEVELOPER_DIR` pins the Command Line Tools SDK, because Homebrew Swift can't read Xcode's
newer one. `snapshot` renders the real launcher on fixture apps and scripts offscreen,
without hotkeys or permissions; `--settings <jsonc>`, `--screen 1512x982` and
`--theme <id>` vary the setup, and `--report` writes the query, rows, selection, overlay,
runs and settings edits as JSON. The dev app (`com.soprano.cast.dev`) has its own
permissions and state, and its command line only reaches the dev app. The design system
(`Sources/SopranoCast/Vendored/`) comes from Soprano; update it with
`scripts/sync-soprano-chrome.sh` instead of editing it here. `docs/ARCHITECTURE.md`
describes the modules, and `docs/ROADMAP.md` lists what is not copied.

## License

[MIT](LICENSE). Departure Mono is © Helena Zhang, SIL Open Font License
(`Support/Licenses/LICENSE-departure-mono`).
