import Foundation

/// Root Search's inline calculator: a recursive-descent parser over the query.
public enum Calculator {
    /// Deepest parenthesis / function / unary nesting accepted.
    static let maxDepth = 64
    static let maxFractionDigits = 10

    /// nil unless `text` is a full expression with at least one operator or function:
    /// + - * / × ÷ ^ %, parentheses, unary minus, decimals with "." or the locale's
    /// decimal separator, functions sqrt abs round floor ceil sin cos tan log (10) ln exp,
    /// constants pi π e. Division by zero, NaN and ∞ → nil.
    ///
    /// Precedence, loosest first: + -, then * / × ÷, then unary minus, then postfix %
    /// (÷ 100), then ^ (right-associative, so `2^3^2` = 512 and `-2^2` = -4). A unary minus
    /// alone doesn't count as an operator ("-5" → nil). Functions need parentheses
    /// ("sqrt(4)"); there is no implicit multiplication ("2pi" → nil). Angles are radians.
    public static func evaluate(_ text: String, locale: Locale) -> CalculatorResult? {
        let expression = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { return nil }
        let decimalSeparator = locale.decimalSeparator.flatMap { $0.count == 1 ? $0.first : nil } ?? "."
        var parser = Parser(characters: Array(expression), decimalSeparator: decimalSeparator)
        guard var value = parser.parse(), parser.sawOperator, value.isFinite else { return nil }
        if value == 0 { value = 0 }  // no "-0"
        return CalculatorResult(expression: expression, value: value, formatted: format(value, locale: locale))
    }

    /// Locale-aware decimal formatting, at most 10 fraction digits, no trailing zeros.
    static func format(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        let formatted = formatter.string(from: NSNumber(value: value)) ?? String(value)
        // Rounding to 10 digits can leave "-0" for tiny negative values.
        return formatter.number(from: formatted)?.doubleValue == 0 ? (formatter.string(from: 0) ?? "0") : formatted
    }

    private enum Function: String {
        case sqrt, abs, round, floor, ceil, sin, cos, tan, log, ln, exp

        func apply(_ x: Double) -> Double {
            switch self {
            case .sqrt: x.squareRoot()
            case .abs: Swift.abs(x)
            case .round: x.rounded()
            case .floor: x.rounded(.down)
            case .ceil: x.rounded(.up)
            case .sin: Foundation.sin(x)
            case .cos: Foundation.cos(x)
            case .tan: Foundation.tan(x)
            case .log: log10(x)
            case .ln: Foundation.log(x)
            case .exp: Foundation.exp(x)
            }
        }
    }

    /// Grammar:
    ///
    ///     expression := term (("+" | "-") term)*
    ///     term       := unary (("*" | "/" | "×" | "÷") unary)*
    ///     unary      := "-" unary | percent
    ///     percent    := power "%"*
    ///     power      := primary ("^" exponent)?
    ///     exponent   := "-" exponent | power
    ///     primary    := number | constant | function "(" expression ")" | "(" expression ")"
    ///
    /// Every rule returns nil on a syntax error or a non-finite intermediate value.
    private struct Parser {
        let characters: [Character]
        let decimalSeparator: Character
        var position = 0
        var depth = 0
        /// A binary operator, "%" or a function was used.
        var sawOperator = false

        init(characters: [Character], decimalSeparator: Character) {
            self.characters = characters
            self.decimalSeparator = decimalSeparator
        }

        mutating func parse() -> Double? {
            guard let value = expression() else { return nil }
            skipWhitespace()
            return position == characters.count ? value : nil
        }

        // MARK: Rules

        private mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while true {
                if consume("+") {
                    guard let rhs = term() else { return nil }
                    value += rhs
                } else if consume("-") || consume("−") {
                    guard let rhs = term() else { return nil }
                    value -= rhs
                } else {
                    return finite(value)
                }
                sawOperator = true
                guard value.isFinite else { return nil }
            }
        }

        private mutating func term() -> Double? {
            guard var value = unary() else { return nil }
            while true {
                if consume("*") || consume("×") {
                    guard let rhs = unary() else { return nil }
                    value *= rhs
                } else if consume("/") || consume("÷") {
                    guard let rhs = unary(), rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    return finite(value)
                }
                sawOperator = true
                guard value.isFinite else { return nil }
            }
        }

        private mutating func unary() -> Double? {
            if consume("-") || consume("−") {
                return nested { parser in parser.unary().map { -$0 } }
            }
            return percent()
        }

        private mutating func percent() -> Double? {
            guard var value = power() else { return nil }
            while consume("%") {
                value /= 100
                sawOperator = true
            }
            return value
        }

        private mutating func power() -> Double? {
            guard let base = primary() else { return nil }
            guard consume("^") else { return base }
            guard let raised = exponent() else { return nil }
            sawOperator = true
            return finite(pow(base, raised))
        }

        private mutating func exponent() -> Double? {
            if consume("-") || consume("−") {
                return nested { parser in parser.exponent().map { -$0 } }
            }
            return nested { $0.power() }
        }

        private mutating func primary() -> Double? {
            skipWhitespace()
            guard position < characters.count else { return nil }
            let character = characters[position]
            if character == "(" {
                position += 1
                return nested { parser in
                    guard let value = parser.expression(), parser.consume(")") else { return nil }
                    return value
                }
            }
            if character == "π" {
                position += 1
                return .pi
            }
            if character.isASCII && character.isLetter {
                return identifier()
            }
            return number()
        }

        /// A constant, or a function applied to its parenthesized argument.
        private mutating func identifier() -> Double? {
            var name = ""
            while position < characters.count, characters[position].isASCII, characters[position].isLetter {
                name.append(characters[position])
                position += 1
            }
            switch name.lowercased() {
            case "pi": return .pi
            case "e": return M_E
            default:
                guard let function = Function(rawValue: name.lowercased()), consume("(") else { return nil }
                return nested { parser in
                    guard let argument = parser.expression(), parser.consume(")") else { return nil }
                    parser.sawOperator = true
                    return parser.finite(function.apply(argument))
                }
            }
        }

        /// ASCII digits with at most one "." or locale decimal separator, and at least one digit.
        private mutating func number() -> Double? {
            var digits = ""
            var sawSeparator = false
            while position < characters.count {
                let character = characters[position]
                if character.isASCII, character.isNumber {
                    digits.append(character)
                } else if character == "." || character == decimalSeparator {
                    guard !sawSeparator else { return nil }
                    sawSeparator = true
                    digits.append(".")
                } else {
                    break
                }
                position += 1
            }
            guard digits.contains(where: { $0 != "." }) else { return nil }
            if digits.hasPrefix(".") { digits = "0" + digits }
            if digits.hasSuffix(".") { digits += "0" }
            guard let value = Double(digits) else { return nil }
            return finite(value)
        }

        // MARK: Helpers

        /// Runs a nested rule, failing past `Calculator.maxDepth`.
        private mutating func nested(_ rule: (inout Parser) -> Double?) -> Double? {
            guard depth < Calculator.maxDepth else { return nil }
            depth += 1
            defer { depth -= 1 }
            return rule(&self)
        }

        private mutating func consume(_ character: Character) -> Bool {
            skipWhitespace()
            guard position < characters.count, characters[position] == character else { return false }
            position += 1
            return true
        }

        private mutating func skipWhitespace() {
            while position < characters.count, characters[position].isWhitespace {
                position += 1
            }
        }

        private func finite(_ value: Double) -> Double? {
            value.isFinite ? value : nil
        }
    }
}
