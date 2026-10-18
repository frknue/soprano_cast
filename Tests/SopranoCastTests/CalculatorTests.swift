import AppKit
import Testing
@testable import SopranoCastCore

struct CalculatorTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    private func value(_ text: String, locale: Locale? = nil) -> Double? {
        Calculator.evaluate(text, locale: locale ?? english)?.value
    }

    private func isClose(_ text: String, _ expected: Double, locale: Locale? = nil) -> Bool {
        guard let result = value(text, locale: locale) else { return false }
        return abs(result - expected) < 1e-9
    }

    @Test("multiplication and division bind tighter than addition and subtraction, left to right")
    func precedence() {
        #expect(value("2+3*4") == 14)
        #expect(value("(2+3)*4") == 20)
        #expect(value("10-4-3") == 3)
        #expect(value("8/4/2") == 1)
        #expect(value("3 × 4 ÷ 2") == 6)
        #expect(value(" 2 * ( 3 + 4 ) ") == 14)
    }

    @Test("power is right-associative and binds tighter than unary minus")
    func power() {
        #expect(value("2^3^2") == 512)
        #expect(value("-2^2") == -4)
        #expect(value("(-2)^2") == 4)
        #expect(value("2^-1") == 0.5)
        #expect(value("2*-3") == -6)
        #expect(value("1--1") == 2)
    }

    @Test("percent is a postfix division by 100")
    func percent() {
        #expect(value("50%") == 0.5)
        #expect(value("200*10%") == 20)
        #expect(value("10^2%") == 1)
        #expect(value("(20+30)%") == 0.5)
    }

    @Test("functions and constants")
    func functions() {
        #expect(value("sqrt(16)") == 4)
        #expect(value("abs(-3)") == 3)
        #expect(value("round(2.5)") == 3)
        #expect(value("floor(2.7)") == 2)
        #expect(value("ceil(2.1)") == 3)
        #expect(isClose("log(1000)", 3))
        #expect(isClose("ln(e)", 1))
        #expect(value("exp(0)") == 1)
        #expect(value("sin(0)") == 0)
        #expect(isClose("cos(pi)", -1))
        #expect(isClose("2*π", 2 * Double.pi))
        #expect(isClose("SQRT(4) + PI", 2 + Double.pi))
        #expect(isClose("tan(pi/4)", 1))
    }

    @Test("the locale's decimal separator and the dot both work")
    func decimalSeparators() {
        #expect(value("1,5*2", locale: german) == 3)
        #expect(value("1.5*2", locale: german) == 3)
        #expect(value("1.5*2") == 3)
        #expect(value(".5+1") == 1.5)
        #expect(value("1,5*2") == nil)
        #expect(value("1,5,2*2", locale: german) == nil)
    }

    @Test("anything that isn't a full calculation is nil")
    func invalid() {
        for text in ["", "   ", "42", "pi", "π", "-5", "(5)", "2pi", "2(3)", "2+", "*2", "()", "2 3",
                     "sqrt 4", "sqrt(4", "foo(2)", "1..2+1", "5 % 3", "hello", "chrome", "2+x"] {
            #expect(Calculator.evaluate(text, locale: english) == nil, "\(text)")
        }
    }

    @Test("division by zero, NaN and infinity are nil")
    func nonFinite() {
        #expect(value("1/0") == nil)
        #expect(value("0/0") == nil)
        #expect(value("5/(2-2)") == nil)
        #expect(value("sqrt(-1)") == nil)
        #expect(value("ln(-1)") == nil)
        #expect(value("10^400") == nil)
    }

    @Test("answers format for the locale with at most 10 fraction digits and no trailing zeros")
    func formatting() {
        #expect(Calculator.evaluate("1/3", locale: english)?.formatted == "0.3333333333")
        #expect(Calculator.evaluate("0.1+0.2", locale: english)?.formatted == "0.3")
        #expect(Calculator.evaluate("1000*1000", locale: english)?.formatted == "1,000,000")
        #expect(Calculator.evaluate("10/4", locale: german)?.formatted == "2,5")
        #expect(Calculator.evaluate("1000*1000", locale: german)?.formatted == "1.000.000")
        #expect(Calculator.evaluate("-1*0", locale: english)?.formatted == "0")
        #expect(Calculator.evaluate("2-5", locale: english)?.formatted == "-3")
    }

    @Test("the result keeps the trimmed expression")
    func expression() {
        let result = Calculator.evaluate("  2 + 2 ", locale: english)
        #expect(result == CalculatorResult(expression: "2 + 2", value: 4, formatted: "4"))
    }
}
