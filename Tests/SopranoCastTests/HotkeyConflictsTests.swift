import AppKit
import Testing
@testable import SopranoCastCore

struct HotkeyConflictsTests {
    private let chrome = HotkeyTarget.item(ItemID(rawValue: "app:com.google.Chrome"))
    private let slack = HotkeyTarget.item(ItemID(rawValue: "app:com.tinyspeck.slackmacgap"))
    private let leftHalf = HotkeyTarget.item(ItemID(rawValue: "window:leftHalf"))

    private func binding(_ text: String, _ target: HotkeyTarget) -> HotkeyBinding {
        HotkeyBinding(spec: HotkeySpec(settingsText: text)!, target: target)
    }

    private func spec(_ text: String) -> HotkeySpec {
        HotkeySpec(settingsText: text)!
    }

    @Test("two targets on the same combo conflict once, listing both")
    func sameCombo() {
        let bindings = [
            binding("cmd+1", chrome), binding("cmd+space", .launcher), binding("command+1", slack),
            binding("cmd+2", leftHalf),
        ]
        let conflicts = HotkeyConflicts.conflicts(in: bindings, hyperIncludesShift: true)
        #expect(conflicts == [HotkeyConflict(spec: spec("cmd+1"), targets: [chrome, slack], reason: .same)])
    }

    @Test("bindings of one target never conflict with each other")
    func sameTarget() {
        let bindings = [binding("cmd+1", chrome), binding("cmd+1", chrome), binding("opt", chrome), binding("double:opt", chrome)]
        #expect(HotkeyConflicts.conflicts(in: bindings, hyperIncludesShift: true).isEmpty)
    }

    @Test("hyper equals the explicit modifiers it expands to, with or without shift")
    func hyperExpansion() {
        let withShift = [binding("hyper+k", chrome), binding("ctrl+opt+shift+cmd+k", slack)]
        #expect(HotkeyConflicts.conflicts(in: withShift, hyperIncludesShift: true)
            == [HotkeyConflict(spec: spec("hyper+k"), targets: [chrome, slack], reason: .same)])
        #expect(HotkeyConflicts.conflicts(in: withShift, hyperIncludesShift: false).isEmpty)

        let withoutShift = [binding("hyper+k", chrome), binding("ctrl+opt+cmd+k", slack)]
        #expect(HotkeyConflicts.conflicts(in: withoutShift, hyperIncludesShift: false)
            == [HotkeyConflict(spec: spec("hyper+k"), targets: [chrome, slack], reason: .same)])
        #expect(HotkeyConflicts.conflicts(in: withoutShift, hyperIncludesShift: true).isEmpty)
    }

    @Test("a modifier tap cannot coexist with a double tap of that modifier on an overlapping side")
    func tapVersusDoubleTap() {
        let cases: [(String, String, Bool)] = [
            ("opt", "double:opt", true),
            ("ropt", "double:ropt", true),
            ("ropt", "double:opt", true),
            ("opt", "double:lopt", true),
            ("lopt", "double:ropt", false),
            ("cmd", "double:opt", false),
            ("cmd+opt", "double:cmd", false),
            ("fn", "double:fn", true),
        ]
        for (tap, double, conflicts) in cases {
            let found = HotkeyConflicts.conflicts(in: [binding(tap, chrome), binding(double, slack)], hyperIncludesShift: true)
            let expected = conflicts ? [HotkeyConflict(spec: spec(tap), targets: [chrome, slack], reason: .cannotCoexist)] : []
            #expect(found == expected, "\(tap) vs \(double)")
        }
    }

    @Test("an any-side tap cannot coexist with both sides of that modifier; a sided tap can")
    func tapVersusBothSides() {
        let anySide = HotkeyConflicts.conflicts(in: [binding("both:cmd", chrome), binding("cmd", slack)], hyperIncludesShift: true)
        #expect(anySide == [HotkeyConflict(spec: spec("both:cmd"), targets: [chrome, slack], reason: .cannotCoexist)])
        #expect(HotkeyConflicts.conflicts(in: [binding("both:cmd", chrome), binding("rcmd", slack)], hyperIncludesShift: true).isEmpty)
        #expect(HotkeyConflicts.conflicts(in: [binding("both:cmd", chrome), binding("double:cmd", slack)], hyperIncludesShift: true).isEmpty)
    }

    @Test("the owner is the other target using the spec or one that cannot coexist with it")
    func owner() {
        let bindings = [binding("cmd+space", .launcher), binding("cmd+1", chrome), binding("opt", slack), binding("hyper+k", leftHalf)]
        #expect(HotkeyConflicts.owner(of: spec("cmd+space"), in: bindings, except: chrome, hyperIncludesShift: true) == .launcher)
        #expect(HotkeyConflicts.owner(of: spec("cmd+1"), in: bindings, except: nil, hyperIncludesShift: true) == chrome)
        #expect(HotkeyConflicts.owner(of: spec("cmd+1"), in: bindings, except: chrome, hyperIncludesShift: true) == nil)
        #expect(HotkeyConflicts.owner(of: spec("double:opt"), in: bindings, except: chrome, hyperIncludesShift: true) == slack)
        #expect(HotkeyConflicts.owner(of: spec("ctrl+opt+shift+cmd+k"), in: bindings, except: nil, hyperIncludesShift: true) == leftHalf)
        #expect(HotkeyConflicts.owner(of: spec("ctrl+opt+shift+cmd+k"), in: bindings, except: nil, hyperIncludesShift: false) == nil)
        #expect(HotkeyConflicts.owner(of: spec("cmd+2"), in: bindings, except: nil, hyperIncludesShift: true) == nil)
    }
}
