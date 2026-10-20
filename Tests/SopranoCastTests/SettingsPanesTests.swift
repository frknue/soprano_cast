import AppKit
import Testing
@testable import SopranoCastCore

struct SettingsPanesTests {
    private let folder = "/System/Library/ExtensionKit/Extensions"

    /// An `.appex` Info.plist like the ones in /System/Library/ExtensionKit/Extensions.
    private func info(id: String = "com.apple.BluetoothSettings", name: String? = "Bluetooth",
                      extensionPoint: String = "com.apple.Settings.extension.ui", allowsURL: Bool? = true,
                      representations: [[String: Any]]? = nil) -> [String: Any] {
        var settings: [String: Any] = [:]
        if let allowsURL { settings["allowsXAppleSystemPreferencesURLScheme"] = allowsURL }
        if let representations { settings["representations"] = representations }
        var info: [String: Any] = [
            "CFBundleIdentifier": id,
            "EXAppExtensionAttributes": [
                "EXExtensionPointIdentifier": extensionPoint,
                "SettingsExtensionAttributes": settings,
            ] as [String: Any],
        ]
        if let name { info["CFBundleName"] = name }
        return info
    }

    private func pane(_ info: [String: Any], path: String = "/System/Library/ExtensionKit/Extensions/Bluetooth.appex",
                      infoStrings: [String: [String: Any]] = [:], localizable: [String: [String: Any]] = [:],
                      languages: [String] = ["en-US"], facts: [String: Bool] = [:],
                      preferences: [String: Bool] = [:]) -> CastItem? {
        SettingsPanes.extensionItem(
            path: path, info: info, infoStrings: infoStrings, localizable: localizable,
            preferredLanguages: languages, facts: SettingsPaneFacts(values: facts),
            preference: { domain, key in preferences["\(domain)/\(key)"] }
        )
    }

    /// PowerPreferences.appex's two representations, verbatim.
    private var power: [[String: Any]] {
        [
            ["predicate": "powersource.battery != YES", "sidebar-name": "ENERGY_SAVER_PREF_TITLE"],
            ["predicate": "powersource.battery == YES", "sidebar-name": "BATTERY_PREF_TITLE"],
        ]
    }

    private var powerStrings: [String: [String: Any]] {
        [
            "en": ["BATTERY_PREF_TITLE": "Battery", "ENERGY_SAVER_PREF_TITLE": "Energy"],
            "de": ["BATTERY_PREF_TITLE": "Batterie", "ENERGY_SAVER_PREF_TITLE": "Energie"],
        ]
    }

    @Test("a System Settings pane becomes a pane item that opens by its bundle id")
    func extensionItem() {
        let item = pane(info())
        #expect(item == CastItem(
            id: ItemID(rawValue: "pane:com.apple.BluetoothSettings"),
            title: "Bluetooth",
            subtitle: "System Settings",
            icon: .file(path: "\(folder)/Bluetooth.appex")
        ))
        #expect(item?.kind == .settingsPane)
        #expect(item?.kind?.label == "Command")
    }

    @Test("extensions of other extension points and panes without URL support are skipped")
    func skipsNonPanes() {
        #expect(pane(info(extensionPoint: "com.apple.widgetkit-extension")) == nil)
        #expect(pane(info(allowsURL: nil)) == nil)
        #expect(pane(info(allowsURL: false)) == nil)
        #expect(pane(info(id: "  ")) == nil)
        #expect(pane(["CFBundleIdentifier": "com.apple.BluetoothSettings", "CFBundleName": "Bluetooth"]) == nil)
    }

    @Test("the name comes from the preferred InfoPlist loctable, with the English name as a keyword")
    func localizedName() {
        let strings: [String: [String: Any]] = [
            "en": ["CFBundleDisplayName": "Accessibility"],
            "de": ["CFBundleDisplayName": "Bedienungshilfen"],
            "LocProvenance": ["en": 1, "de": 1],
        ]
        let accessibility = info(id: "com.apple.Accessibility-Settings.extension", name: "AccessibilitySettingsExtension")
        let german = pane(accessibility, infoStrings: strings, languages: ["de-DE"])
        #expect(german?.title == "Bedienungshilfen")
        #expect(german?.keywords == ["Accessibility"])

        let english = pane(accessibility, infoStrings: strings, languages: ["en-US"])
        #expect(english?.title == "Accessibility")
        #expect(english?.keywords == [])

        let japanese = pane(accessibility, infoStrings: strings, languages: ["ja-JP"])
        #expect(japanese?.title == "Accessibility")
    }

    @Test("without a loctable name the Info.plist display name, then bundle name, is used")
    func infoNameFallback() {
        var withDisplayName = info(name: "BluetoothExt")
        withDisplayName["CFBundleDisplayName"] = " Bluetooth "
        #expect(pane(withDisplayName)?.title == "Bluetooth")
        #expect(pane(info(name: "Bluetooth"), infoStrings: ["en": ["CFBundleName": "Other"]])?.title == "Bluetooth")
        #expect(pane(info(name: nil)) == nil)
    }

    @Test("internal names ending in Extension are not listed")
    func internalNames() {
        #expect(pane(info(id: "com.apple.HeadphoneSettings", name: "HeadphoneSettingsExtension")) == nil)
    }

    @Test("the representation true on this Mac names the pane from Localizable")
    func representationNames() {
        let laptop = pane(info(id: "com.apple.Battery-Settings.extension", name: "PowerPreferences", representations: power),
                          localizable: powerStrings, facts: ["powersource.battery": true])
        #expect(laptop?.title == "Battery")
        let desktop = pane(info(id: "com.apple.Battery-Settings.extension", name: "PowerPreferences", representations: power),
                           localizable: powerStrings, facts: ["powersource.battery": false])
        #expect(desktop?.title == "Energy")
        let german = pane(info(id: "com.apple.Battery-Settings.extension", name: "PowerPreferences", representations: power),
                          localizable: powerStrings, languages: ["de-DE"], facts: ["powersource.battery": true])
        #expect(german?.title == "Batterie")
        #expect(german?.keywords == ["Battery"])
    }

    @Test("a sidebar name missing from Localizable is used as written")
    func literalSidebarName() {
        let touchID: [[String: Any]] = [
            ["predicate": "user.isguest == YES", "hidden": true],
            ["predicate": "device.touchID != YES", "sidebar-name": "Login Password"],
            ["predicate": "device.touchID == YES", "sidebar-name": "Touch ID & Password"],
        ]
        let item = pane(info(id: "com.apple.Touch-ID-Settings.extension", name: "Touch ID & Password", representations: touchID),
                        facts: ["user.isguest": false, "device.touchID": false])
        #expect(item?.title == "Login Password")
        let guest = pane(info(id: "com.apple.Touch-ID-Settings.extension", name: "Touch ID & Password", representations: touchID),
                         facts: ["user.isguest": true, "device.touchID": true])
        #expect(guest == nil)
    }

    @Test("a hidden representation that is true on this Mac hides the pane")
    func hiddenRepresentation() {
        let cds: [[String: Any]] = [
            ["predicate": "device.cddvd == YES"],
            ["predicate": "device.cddvd != YES", "hidden": true],
        ]
        let cdInfo = info(id: "com.apple.CD-DVD-Settings.extension", name: "CDs & DVDs", representations: cds)
        #expect(pane(cdInfo, facts: ["device.cddvd": false]) == nil)
        #expect(pane(cdInfo, facts: ["device.cddvd": true])?.title == "CDs & DVDs")
    }

    @Test("an unknown fact decides nothing: the pane stays listed under its default name")
    func undeterminedFact() {
        let mouse: [[String: Any]] = [
            ["predicate": "device.mouse == YES"],
            ["predicate": "device.mouse != YES", "hidden": true],
        ]
        #expect(pane(info(id: "com.apple.Mouse-Settings.extension", name: "Mouse", representations: mouse))?.title == "Mouse")
        let odd: [[String: Any]] = [["predicate": "device.cddvd >= 3", "hidden": true]]
        #expect(pane(info(name: "Bluetooth", representations: odd), facts: ["device.cddvd": true])?.title == "Bluetooth")
    }

    @Test("values_from_preferences read the predicate key through the preference closure, unset counting as NO")
    func preferenceValues() {
        let source: [[String: Any]] = [["domain": "com.apple.GameController", "key": "showGCPrefsPane"]]
        let controllers: [[String: Any]] = [
            ["predicate": "showGCPrefsPane == YES", "values_from_preferences": source],
            ["predicate": "showGCPrefsPane != YES", "values_from_preferences": source, "hidden": true],
        ]
        let gameInfo = info(id: "com.apple.Game-Controller-Settings.extension", name: "Game Controllers",
                            representations: controllers)
        #expect(pane(gameInfo, preferences: ["com.apple.GameController/showGCPrefsPane": false]) == nil)
        #expect(pane(gameInfo, preferences: ["com.apple.GameController/showGCPrefsPane": true])?.title == "Game Controllers")
        #expect(pane(gameInfo) == nil)
        #expect(pane(gameInfo, facts: ["showGCPrefsPane": true],
                     preferences: ["com.apple.GameController/showGCPrefsPane": false])?.title == "Game Controllers")
    }

    @Test("a non-breaking hyphen in the title adds a plain-hyphen keyword")
    func punctuationKeyword() {
        let item = pane(info(id: "com.apple.wifi-settings-extension", name: "Wi\u{2011}Fi"),
                        path: "\(folder)/Wi-Fi.appex")
        #expect(item?.title == "Wi\u{2011}Fi")
        #expect(item?.keywords == ["Wi-Fi"])
        #expect(pane(info(name: "Date\u{00A0}&\u{00A0}Time"))?.keywords == ["Date & Time"])
    }

    @Test("a legacy prefPane is named by display name, icon label, bundle name, then file name")
    func legacyNames() {
        let path = "/Library/PreferencePanes/Flash Player.prefPane"
        func legacy(_ info: [String: Any], strings: [String: [String: Any]] = [:]) -> CastItem? {
            SettingsPanes.legacyItem(path: path, info: info, infoStrings: strings, preferredLanguages: ["de-DE"])
        }
        let full: [String: Any] = [
            "CFBundleIdentifier": "com.adobe.flashplayerpreferences",
            "CFBundleDisplayName": "Flash Display", "NSPrefPaneIconLabel": "Flash\nPlayer", "CFBundleName": "FlashPlayerPrefs",
        ]
        #expect(legacy(full, strings: ["de": ["CFBundleDisplayName": "Flash Anzeige"]])?.title == "Flash Anzeige")
        #expect(legacy(full)?.title == "Flash Display")
        #expect(legacy(full.filter { $0.key != "CFBundleDisplayName" })?.title == "Flash Player")
        #expect(legacy(["CFBundleIdentifier": "com.adobe.flashplayerpreferences", "CFBundleName": "FlashPlayerPrefs"])?.title
            == "FlashPlayerPrefs")

        let bare = legacy([:])
        #expect(bare == CastItem(
            id: ItemID(rawValue: "pane:\(path)"),
            title: "Flash Player",
            subtitle: "System Settings",
            icon: .file(path: path)
        ))
        #expect(legacy(full)?.id == ItemID(rawValue: "pane:com.adobe.flashplayerpreferences"))
    }

    @Test("panes open by x-apple.systempreferences URL, prefPanes by file, other kinds not at all")
    func targets() throws {
        let bluetooth = try #require(pane(info()))
        #expect(SettingsPanes.target(for: bluetooth) == .url("x-apple.systempreferences:com.apple.BluetoothSettings"))
        let path = "/Users/me/Library/PreferencePanes/Thing.prefPane"
        let thing = try #require(SettingsPanes.legacyItem(path: path, info: [:], infoStrings: [:], preferredLanguages: ["en"]))
        #expect(SettingsPanes.target(for: thing) == .file(path))
        let lowercase = "/Library/PreferencePanes/Old.prefpane"
        let old = try #require(SettingsPanes.legacyItem(path: lowercase, info: [:], infoStrings: [:], preferredLanguages: ["en"]))
        #expect(old.title == "Old")
        #expect(SettingsPanes.target(for: old) == .file(lowercase))
        #expect(SettingsPanes.legacyItem(path: "/Library/PreferencePanes/Old.bundle", info: [:], infoStrings: [:],
                                         preferredLanguages: ["en"]) == nil)
        let app = CastItem(id: ItemID(rawValue: "app:com.apple.systempreferences"), title: "System Settings",
                           icon: .file(path: "/System/Applications/System Settings.app"))
        #expect(SettingsPanes.target(for: app) == nil)
    }
}
