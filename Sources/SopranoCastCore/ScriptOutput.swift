import Foundation

/// Script stdout/stderr cleanup for HUDs, toasts, inline subtitles and the output view.
public enum ScriptOutput {
    /// Removes ANSI escape sequences: CSI (`ESC [ … final`, colors and cursor movement),
    /// OSC (`ESC ] … BEL` or `ESC ] … ESC \`, titles and hyperlinks), character-set
    /// designations (`ESC ( B`) and other two-character escapes. An unterminated sequence
    /// at the end is dropped.
    public static func strippingANSI(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            guard scalars[index] == escape else {
                result.append(scalars[index])
                index += 1
                continue
            }
            index += 1
            guard index < scalars.count else { break }
            let introducer = scalars[index]
            index += 1
            switch introducer {
            case "[":
                // Parameters 0x30–0x3F and intermediates 0x20–0x2F, then one final byte 0x40–0x7E.
                while index < scalars.count, (0x20...0x3F).contains(scalars[index].value) { index += 1 }
                if index < scalars.count, (0x40...0x7E).contains(scalars[index].value) { index += 1 }
            case "]", "P", "X", "^", "_":
                // String sequences (OSC, DCS, SOS, PM, APC) end at BEL or ST (ESC \).
                while index < scalars.count {
                    if scalars[index] == bell { index += 1; break }
                    if scalars[index] == escape, index + 1 < scalars.count, scalars[index + 1] == "\\" {
                        index += 2
                        break
                    }
                    index += 1
                }
            case "(", ")", "*", "+", "-", ".", "/", "#", "%":
                if index < scalars.count { index += 1 }
            default:
                break
            }
        }
        return String(result)
    }

    /// The last non-empty line, ANSI stripped.
    ///
    /// Lines are trimmed; whitespace-only lines count as empty. nil when there is none.
    public static func lastLine(_ text: String) -> String? {
        strippingANSI(text)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty })
    }

    private static let escape: Unicode.Scalar = "\u{1B}"
    private static let bell: Unicode.Scalar = "\u{07}"
}
