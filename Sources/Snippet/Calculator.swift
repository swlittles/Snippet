import Foundation
import Combine

struct Calculation: Codable, Identifiable, Equatable {
    var id = UUID()
    var expression: String
    var result: Double
    var degrees: Bool
    var date = Date()
    var formatted: String { Calculator.format(result) }
}

final class CalculatorStore: ObservableObject {
    @Published private(set) var entries: [Calculation] = []
    @Published var error: String?
    let url: URL
    var answer: Double { entries.first?.result ?? 0 }
    init(url: URL? = nil) {
        self.url = url ?? AppEnvironment.current.dataURL("calculations.json")
        guard FileManager.default.fileExists(atPath: self.url.path) else { return }
        do { entries = try JSONDecoder().decode([Calculation].self, from: Data(contentsOf: self.url)) }
        catch { self.error = "Couldn’t read calculation history. The original file was preserved." }
    }
    @discardableResult func record(expression: String, result: Double, degrees: Bool) -> Bool {
        var next = entries
        let item = Calculation(expression: expression, result: result, degrees: degrees)
        if let first = next.first, first.expression == expression && first.result == result && first.degrees == degrees { return true }
        next.insert(item, at: 0)
        return persist(Array(next.prefix(200)))
    }
    func clear() { _ = persist([]) }
    private func persist(_ next: [Calculation]) -> Bool {
        guard error == nil else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            entries = next; return true
        } catch { self.error = "Couldn’t save calculation history: \(error.localizedDescription)"; return false }
    }
}

enum MathError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

enum Calculator {
    static func format(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%.14g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    static func evaluate(_ expression: String, answer: Double = 0, degrees: Bool = false) throws -> Double {
        guard expression.count <= 1000 else { throw MathError.invalid("Expression is too long (1,000 characters maximum).") }
        var parser = try Parser(expression, answer: answer, degrees: degrees)
        let result = try parser.sum()
        guard parser.current == .end else { throw MathError.invalid("Unexpected input. Check your operators and parentheses.") }
        guard result.isFinite else { throw MathError.invalid("Result is outside the supported number range.") }
        return result
    }
    enum Token: Equatable { case number(Double), name(String), symbol(Character), end }
    struct Parser {
        var tokens: [Token] = []
        var index = 0
        let answer: Double
        let degrees: Bool
        var depth = 0
        var current: Token { tokens[index] }
        init(_ expression: String, answer: Double, degrees: Bool) throws {
            self.answer = answer; self.degrees = degrees
            let normalized = expression.lowercased().replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "π", with: "pi")
            let chars = Array(normalized)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace { i += 1; continue }
                if c.isNumber || c == "." {
                    let start = i
                    while i < chars.count && (chars[i].isNumber || chars[i] == ".") { i += 1 }
                    if i < chars.count && chars[i] == "e" {
                        var end = i + 1
                        if end < chars.count && (chars[end] == "+" || chars[end] == "-") { end += 1 }
                        let digits = end
                        while end < chars.count && chars[end].isNumber { end += 1 }
                        if end > digits { i = end }
                    }
                    guard let number = Double(String(chars[start..<i])), number.isFinite else { throw MathError.invalid("Invalid number.") }
                    tokens.append(.number(number)); continue
                }
                if c.isLetter {
                    let start = i
                    while i < chars.count && chars[i].isLetter { i += 1 }
                    tokens.append(.name(String(chars[start..<i]))); continue
                }
                guard "+-*/^()%!,".contains(c) else { throw MathError.invalid("Unsupported character: \(c)") }
                tokens.append(.symbol(c)); i += 1
            }
            tokens.append(.end)
        }
        mutating func take(_ symbol: Character) -> Bool {
            if current == .symbol(symbol) { index += 1; return true }; return false
        }
        mutating func sum() throws -> Double {
            depth += 1
            defer { depth -= 1 }
            guard depth <= 40 else { throw MathError.invalid("Too many nested expressions.") }
            var value = try product()
            while true {
                if take("+") { value += try product() }
                else if take("-") { value -= try product() }
                else { return value }
            }
        }
        mutating func product() throws -> Double {
            var value = try unary()
            while true {
                if take("*") { value *= try unary() }
                else if take("/") {
                    let divisor = try unary()
                    guard divisor != 0 else { throw MathError.invalid("Cannot divide by zero.") }
                    value /= divisor
                } else if current == .symbol("(") {
                    value *= try unary()
                } else if case .name = current {
                    value *= try unary()
                } else { return value }
            }
        }
        mutating func unary() throws -> Double {
            depth += 1
            defer { depth -= 1 }
            guard depth <= 40 else { throw MathError.invalid("Too many nested operators.") }
            if take("+") { return try unary() }
            if take("-") { return -(try unary()) }
            return try power()
        }
        mutating func power() throws -> Double {
            var value = try primary()
            while true {
                if take("%") { value /= 100 }
                else if take("!") {
                    guard value >= 0, value <= 170, value.rounded() == value else { throw MathError.invalid("Factorial needs an integer from 0 to 170.") }
                    value = value < 2 ? 1 : (2...Int(value)).reduce(1.0) { $0 * Double($1) }
                } else { break }
            }
            if take("^") { value = Foundation.pow(value, try unary()) }
            return value
        }
        mutating func primary() throws -> Double {
            if case .number(let value) = current { index += 1; return value }
            if take("(") {
                let value = try sum()
                guard take(")") else { throw MathError.invalid("Missing closing parenthesis.") }
                return value
            }
            if case .name(let name) = current {
                index += 1
                if name == "pi" { return .pi }
                if name == "e" { return M_E }
                if name == "ans" { return answer }
                guard take("(") else { throw MathError.invalid("Use a function such as sqrt(9), or constants pi, e, ans.") }
                var arguments = [try sum()]
                while take(",") { arguments.append(try sum()) }
                guard take(")") else { throw MathError.invalid("Missing closing parenthesis.") }
                if ["min", "max", "pow"].contains(name) {
                    guard arguments.count == 2 else { throw MathError.invalid("\(name) needs two arguments.") }
                    if name == "min" { return min(arguments[0], arguments[1]) }
                    if name == "max" { return max(arguments[0], arguments[1]) }
                    return Foundation.pow(arguments[0], arguments[1])
                }
                guard arguments.count == 1 else { throw MathError.invalid("\(name) needs one argument.") }
                let x = arguments[0], angle = degrees ? x * .pi / 180 : x
                let result: Double
                switch name {
                case "sqrt": result = sqrt(x)
                case "abs": result = abs(x)
                case "sin": result = sin(angle)
                case "cos": result = cos(angle)
                case "tan":
                    guard abs(cos(angle)) > 1e-14 else { throw MathError.invalid("Tangent is undefined at this angle.") }
                    result = tan(angle)
                case "ln": result = log(x)
                case "log": result = log10(x)
                case "exp": result = exp(x)
                case "round": result = x.rounded()
                case "floor": result = floor(x)
                case "ceil": result = ceil(x)
                default: throw MathError.invalid("Unknown function: \(name)")
                }
                guard result.isFinite else { throw MathError.invalid("\(name) is undefined for this value.") }
                return result
            }
            throw MathError.invalid("Enter a number or expression.")
        }
    }
}
