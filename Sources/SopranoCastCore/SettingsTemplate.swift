import Foundation

/// The commented settings.json written on first launch: the schema is the documentation.
/// Every value is the default, so the template resolves to `CastSettings.defaults`;
/// allowed values and command names are generated from the enums so they never drift.
public enum SettingsTemplate {
    /// The commented settings.json written on first launch. Resolves to `.defaults` with
    /// no issues; documents every key below with its default and allowed values.
    public static let text: String = """
    // Soprano Cast settings. JSON with comments; saved changes apply immediately.
    // Every key is optional. Unknown keys and bad values are ignored with a warning.
    //
    // Item ids name what a hotkey, alias, favorite, disabled entry or fallback refers to:
    //   app:<bundle id>          "app:com.google.Chrome" (or app:<path> for apps without one)
    //   system:<command>         "system:lockScreen"
    //   window:<command>         "window:leftHalf"
    //   quicklink:<id>           "quicklink:github" (an id from "quicklinks" below)
    //   script:<absolute path>   "script:/Users/me/raycast-scripts/hello.sh"
    //   cast:<command>           "cast:searchGoogle"
    //   pane:<bundle id>         "pane:com.apple.BluetoothSettings" (a System Settings pane)
    // Ids of apps that are not installed right now are kept.
    // System commands:
    \(wrapped(SystemCommand.allCases.map(\.rawValue)))
    // Window commands:
    \(wrapped(WindowCommand.allCases.map(\.rawValue)))
    // Soprano Cast commands:
    \(wrapped(CastCommand.allCases.map(\.rawValue)))
    //
    // Hotkeys (case-insensitive, spaces ignored), every shape Raycast supports:
    //   modifiers + key    "cmd+shift+k", "ctrl+opt+left", "cmd+1", "fn+a", "opt+space"
    //                      modifiers: cmd (command, ⌘), opt (option, alt, ⌥), ctrl (control, ⌃),
    //                      shift (⇧), fn; keys: "space", "tab", "return", "escape", "delete",
    //                      "forwardDelete", "left", "right", "up", "down", "home", "end",
    //                      "pageUp", "pageDown", "f1"…"f20", or a printable key one of two ways:
    //     by position      "cmd+key:'", "cmd+key:§", "ctrl+key:z", "cmd+key:0x27": the key at
    //                      that place on a US keyboard (or its key code), whatever the current
    //                      layout types there; "cmd+key:'" stays the key right of L on German
    //                      (where it types ä). Raycast's default; recorded hotkeys use this.
    //     by character     "cmd+'", "cmd+k": the key that types this character on the current
    //                      layout, looked up again when the layout changes
    //   hyper + key        "hyper+1", "hyper+key:k": the Hyper key (⌃⌥⇧⌘, see "hyperKey")
    //   key alone          "f13" … "f20" only
    //   modifier tap       "rcmd", "lopt", "cmd+opt", "fn": press and release only modifiers;
    //                      sided names lcmd rcmd lopt ropt lctrl rctrl lshift rshift,
    //                      plain names take either side
    //   double tap         "double:cmd", "double:rshift": the same modifier twice quickly
    //   both sides         "both:cmd", "both:shift": left and right held together (not fn)
    {
      // "soprano" follows the theme of Soprano (~/.config/soprano/settings.json),
      // or any Soprano theme id.
      "theme": "soprano",

      "launcher": {
        // Opens and closes the launcher; null = no global hotkey.
        "hotkey": "cmd+space",
        // Display the launcher opens on: \(values(LauncherScreen.self))
        "screen": "withMouse",
        // Reopening later than this clears the search and returns to Root Search
        // (\(LauncherSettings.popToRootRange.lowerBound)–\(LauncherSettings.popToRootRange.upperBound) seconds; 0 = always).
        "popToRootSeconds": 90,
        // Extra keys to move the selection besides ↑ ↓: \(values(NavigationBindings.self))
        // (emacs ⌃N/⌃P, vim ⌃J/⌃K)
        "navigation": "emacs",
        // Clicking another app closes the launcher.
        "closeOnFocusLoss": true
      },

      // Global hotkeys per item id, e.g.
      //   "app:com.google.Chrome": "cmd+1",
      //   "window:leftHalf": "ctrl+opt+left",
      //   "system:lockScreen": "double:rcmd"
      // null removes one. Two items on the same hotkey: the later id (sorted) is dropped;
      // a hotkey equal to launcher.hotkey is dropped.
      "hotkeys": {},

      // Root Search aliases per item id, e.g. "app:com.google.Chrome": "gc".
      // Lowercase a–z, 0–9 and spaces; an exact alias match ranks first.
      "aliases": {},

      // Item ids shown in Root Search's Favorites section, in order.
      "favorites": [],

      // Item ids hidden from Root Search (their hotkeys still work).
      "disabled": [],

      // Item ids offered after the results for any query ("Use “x” with …").
      "fallbacks": ["cast:searchGoogle"],

      // Quicklinks, each a Root Search item "quicklink:<id>":
      //   id        required, a–z, 0–9 and "-", unique
      //   name      required, the title in Root Search
      //   link      required: a URL, file or folder path (~ allowed) or deeplink, with
      //             placeholders {argument name="repo"} (add default="x" to make it optional),
      //             {argument}, {Query}, {clipboard}, {date}, {time}, {uuid};
      //             inside the JSON string write each " as \\"
      //   openWith  optional: bundle id, app name or app path (default: the system default)
      //   icon      optional: an emoji or image path
      // e.g. { "id": "github", "name": "GitHub Repo",
      //        "link": "https://github.com/{argument name=\\"repo\\"}",
      //        "openWith": "com.google.Chrome", "icon": "🐙" }
      "quicklinks": [],

      // Folders of Raycast-format script commands (~ allowed), e.g. ["~/raycast-scripts"].
      "scriptDirectories": [],

      // Extra folders searched for applications besides /Applications and friends.
      "applicationDirectories": [],

      // The Hyper key: holding the trigger holds ⌃⌥⇧⌘ (⌃⌥⌘ without includeShift), so
      // "hyper+k" hotkeys never clash with app shortcuts. Needs Accessibility.
      "hyperKey": {
        // \(values(HyperTrigger.self)) or null (no Hyper key)
        "trigger": null,
        "includeShift": true,
        // Tapping Caps Lock alone (trigger "capsLock" only): \(values(HyperQuickPress.self))
        "quickPress": "nothing"
      },

      "windowManagement": {
        // Points between windows and the display edge (\(WindowManagementSettings.gapRange.lowerBound)–\(WindowManagementSettings.gapRange.upperBound)).
        "gap": 0,
        // Pressing Left/Right Half again: \(values(HalvesBehavior.self))
        // (cycleSizes ½ → ⅔ → ⅓; moveToDisplay moves on to the next display)
        "halves": "stay"
      },

      "app": {
        "startAtLogin": true,
        "showMenuBarIcon": true
      }
    }

    """

    /// `"a" | "b" | "c"` for an enum's settings.json spellings.
    private static func values<Value: RawRepresentable & CaseIterable>(_: Value.Type) -> String where Value.RawValue == String {
        Value.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: " | ")
    }

    /// `names` as comment lines of at most about 90 columns ("//   a, b, c,").
    private static func wrapped(_ names: [String]) -> String {
        let prefix = "//   "
        var lines: [String] = []
        var line = prefix
        for (index, name) in names.enumerated() {
            let word = index == names.count - 1 ? name : name + ","
            if line != prefix, line.count + 1 + word.count > 90 {
                lines.append(line)
                line = prefix
            }
            line += line == prefix ? word : " " + word
        }
        lines.append(line)
        return lines.joined(separator: "\n")
    }
}
