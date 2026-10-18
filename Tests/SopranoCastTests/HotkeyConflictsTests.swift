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

    @Test("with the default resolver a physical key equals only the same position, never a character key")
    func physicalKeys() {
        let samePosition = [binding("cmd+key:'", chrome), binding("command+key:0x27", slack)]
        #expect(HotkeyConflicts.conflicts(in: samePosition, hyperIncludesShift: true)
            == [HotkeyConflict(spec: spec("cmd+key:'"), targets: [chrome, slack], reason: .same)])
        #expect(HotkeyConflicts.conflicts(in: [binding("cmd+key:'", chrome), binding("cmd+'", slack)], hyperIncludesShift: true).isEmpty)
        #expect(HotkeyConflicts.conflicts(in: [binding("cmd+key:'", chrome), binding("cmd+key:;", slack)], hyperIncludesShift: true).isEmpty)
        #expect(HotkeyConflicts.owner(of: spec("hyper+key:1"), in: [binding("ctrl+opt+shift+cmd+key:1", chrome)], except: nil, hyperIncludesShift: true) == chrome)
    }

    @Test("a layout-aware resolver makes a physical key meet the character key it types")
    func resolvedCharacterKeys() {
        let layout: (KeySpec) -> UInt16? = { key in
            key == .character("k") ? 0x28 : HotkeyConflicts.positionalKeyCode(key)
        }
        let bindings = [binding("shift+cmd+k", chrome), binding("shift+cmd+key:k", slack)]
        #expect(HotkeyConflicts.conflicts(in: bindings, hyperIncludesShift: true, keyCode: layout)
            == [HotkeyConflict(spec: spec("shift+cmd+k"), targets: [chrome, slack], reason: .same)])
        #expect(HotkeyConflicts.conflicts(in: bindings, hyperIncludesShift: true).isEmpty)
        #expect(HotkeyConflicts.owner(of: spec("shift+cmd+key:k"), in: bindings, except: slack, hyperIncludesShift: true, keyCode: layout) == chrome)
        #expect(HotkeyConflicts.owner(of: spec("shift+cmd+key:k"), in: bindings, except: slack, hyperIncludesShift: true) == nil)
        #expect(HotkeyConflicts.owner(of: spec("shift+cmd+j"), in: bindings, except: nil, hyperIncludesShift: true, keyCode: layout) == nil)
    }

    @Test("a named key and a physical key with the same key code are the same")
    func namedVersusPhysical() {
        let bindings = [
            HotkeyBinding(spec: .combo(HotkeyCombo(modifiers: .command, key: .named(.return))), target: chrome),
            HotkeyBinding(spec: .combo(HotkeyCombo(modifiers: .command, key: .physical(0x24))), target: slack),
        ]
        #expect(HotkeyConflicts.conflicts(in: bindings, hyperIncludesShift: true)
            == [HotkeyConflict(spec: bindings[0].spec, targets: [chrome, slack], reason: .same)])
        #expect(HotkeyConflicts.positionalKeyCode(.named(.return)) == 0x24)
        #expect(HotkeyConflicts.positionalKeyCode(.physical(0x27)) == 0x27)
        #expect(HotkeyConflicts.positionalKeyCode(.character("k")) == nil)
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
