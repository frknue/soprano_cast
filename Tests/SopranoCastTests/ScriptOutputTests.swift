import AppKit
import Testing
@testable import SopranoCastCore

struct ScriptOutputTests {
    @Test("colors, styles and cursor sequences are stripped")
    func csi() {
        #expect(ScriptOutput.strippingANSI("\u{1B}[1;31mError\u{1B}[0m: bad") == "Error: bad")
        #expect(ScriptOutput.strippingANSI("\u{1B}[38;5;208morange\u{1B}[m") == "orange")
        #expect(ScriptOutput.strippingANSI("\u{1B}[2K\u{1B}[1Gdone\u{1B}[?25h") == "done")
    }

    @Test("OSC titles and hyperlinks are stripped with BEL or ST terminators")
    func osc() {
        #expect(ScriptOutput.strippingANSI("\u{1B}]0;title\u{07}text") == "text")
        #expect(ScriptOutput.strippingANSI("\u{1B}]8;;https://x.example\u{1B}\\link\u{1B}]8;;\u{1B}\\ after") == "link after")
    }

    @Test("charset designations and lone escapes are stripped, plain text and emoji survive")
    func others() {
        #expect(ScriptOutput.strippingANSI("\u{1B}(Bplain") == "plain")
        #expect(ScriptOutput.strippingANSI("a\u{1B}=b") == "ab")
        #expect(ScriptOutput.strippingANSI("✅ ünïcode [not ansi]") == "✅ ünïcode [not ansi]")
        #expect(ScriptOutput.strippingANSI("cut\u{1B}[31") == "cut")
        #expect(ScriptOutput.strippingANSI("end\u{1B}") == "end")
    }

    @Test("the last line is the last non-empty one, trimmed and stripped")
    func lastLine() {
        #expect(ScriptOutput.lastLine("one\ntwo\n\n  \n") == "two")
        #expect(ScriptOutput.lastLine("first\r\n  \u{1B}[32mDone!\u{1B}[0m  \r\n") == "Done!")
        #expect(ScriptOutput.lastLine("value\n\u{1B}[0m\n") == "value")
        #expect(ScriptOutput.lastLine("single") == "single")
        #expect(ScriptOutput.lastLine("") == nil)
        #expect(ScriptOutput.lastLine(" \n\t\n") == nil)
    }
}
