import Foundation
import CryptoKit

struct ExpandedTemplate: Equatable {
    var text: String
    var cursorMoves: Int
}
enum SnippetTemplate {
    static let pattern = try! NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
    static func tokens(_ text: String) -> [String] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) }
        }
    }
    static func fields(_ text: String) -> [String] {
        var seen = Set<String>()
        return tokens(text).filter { !["date", "time", "clipboard", "cursor", "uuid"].contains($0) && !$0.hasPrefix("date:") && seen.insert($0).inserted }
    }
    static func expand(_ text: String, values: [String: String] = [:], clipboard: String = "", now: Date = Date()) -> ExpandedTemplate {
        var output = "", end = text.startIndex, cursor: Int?
        let uuid = UUID().uuidString
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let keyRange = Range(match.range(at: 1), in: text) else { continue }
            output += text[end..<range.lowerBound]
            let key = text[keyRange].trimmingCharacters(in: .whitespaces)
            switch key {
            case "cursor": if cursor == nil { cursor = output.count }
            case "clipboard": output += clipboard
            case "uuid": output += uuid
            case "date", "time":
                let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.dateFormat = key == "date" ? "yyyy-MM-dd" : "HH:mm"
                output += format.string(from: now)
            default:
                if key.hasPrefix("date:") {
                    let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.dateFormat = String(key.dropFirst(5)); output += format.string(from: now)
                } else { output += values[key] ?? String(text[range]) }
            }
            end = range.upperBound
        }
        output += text[end...]
        return ExpandedTemplate(text: output, cursorMoves: cursor.map { output.count - $0 } ?? 0)
    }
}

enum TextTool: String, CaseIterable, Identifiable {
    case json = "Format JSON", compactJSON = "Minify JSON", upper = "UPPERCASE", lower = "lowercase", title = "Title Case"
    case trim = "Trim whitespace", deduplicate = "Deduplicate lines", sort = "Sort lines", cleanURL = "Remove URL trackers"
    case base64Encode = "Base64 encode", base64Decode = "Base64 decode", urlEncode = "URL encode", urlDecode = "URL decode"
    case sha256 = "SHA-256", uuid = "Generate UUID", timestamp = "Unix timestamp → date", now = "Current Unix timestamp"
    case jwt = "Inspect JWT payload", escape = "JSON escape string", unescape = "JSON unescape string"
    var id: String { rawValue }
    func apply(_ input: String) throws -> String {
        switch self {
        case .json, .compactJSON:
            let object = try JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed])
            return String(decoding: try JSONSerialization.data(withJSONObject: object, options: self == .json ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed] : [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
        case .upper: return input.uppercased()
        case .lower: return input.lowercased()
        case .title: return input.capitalized
        case .trim: return input.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        case .deduplicate:
            var seen = Set<String>(); return input.components(separatedBy: "\n").filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .sort: return input.components(separatedBy: "\n").sorted().joined(separator: "\n")
        case .cleanURL:
            guard var url = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw MathError.invalid("Enter an http or https URL.") }
            url.queryItems = url.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid"].contains($0.name.lowercased()) }
            if url.queryItems?.isEmpty == true { url.queryItems = nil }; return url.string ?? input
        case .base64Encode: return Data(input.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)), let text = String(data: data, encoding: .utf8) else { throw MathError.invalid("Not valid Base64 UTF-8 text.") }; return text
        case .urlEncode: return input.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? input
        case .urlDecode:
            guard let text = input.removingPercentEncoding else { throw MathError.invalid("Invalid URL encoding.") }; return text
        case .sha256: return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        case .uuid: return UUID().uuidString
        case .now: return String(Int(Date().timeIntervalSince1970))
        case .timestamp:
            guard let seconds = Double(input.trimmingCharacters(in: .whitespacesAndNewlines)), seconds.isFinite, abs(seconds) < 253402300800 else { throw MathError.invalid("Enter a Unix timestamp in seconds.") }
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
        case .jwt:
            let pieces = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
            guard pieces.count == 3 else { throw MathError.invalid("A JWT has three dot-separated segments. This tool does not verify its signature.") }
            var payload = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            return try TextTool.json.apply(TextTool.base64Decode.apply(payload))
        case .escape: return String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        case .unescape: return try JSONDecoder().decode(String.self, from: Data(input.utf8))
        }
    }
}

struct NaturalResult: Equatable { var value: Double; var display: String }
enum NaturalCalculator {
    static func groups(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
    static func evaluate(_ input: String, now: Date = Date()) throws -> NaturalResult? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let g = groups(#"^(.+)%\s+of\s+(.+)$"#, input) {
            let value = try Calculator.evaluate(g[0]) / 100 * Calculator.evaluate(g[1]); return .init(value: value, display: Calculator.format(value))
        }
        if let g = groups(#"^(today|\d{4}-\d{2}-\d{2})\s*([+-])\s*(\d+)\s*(days?|weeks?|months?|years?)$"#, input) {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            guard let date = g[0].lowercased() == "today" ? Calendar.current.startOfDay(for: now) : formatter.date(from: g[0]), let count = Int(g[2]), count <= 100_000 else { throw MathError.invalid("Use a valid date and a smaller date offset.") }
            let component: Calendar.Component = g[3].lowercased().hasPrefix("week") ? .weekOfYear : g[3].lowercased().hasPrefix("month") ? .month : g[3].lowercased().hasPrefix("year") ? .year : .day
            guard let end = Calendar.current.date(byAdding: component, value: count * (g[1] == "-" ? -1 : 1), to: date) else { throw MathError.invalid("Date is out of range.") }
            return .init(value: end.timeIntervalSince1970, display: formatter.string(from: end))
        }
        if let g = groups(#"^(.+?)\s+([a-z°]+)\s+(?:to|in)\s+([a-z°]+)$"#, input) {
            let x = try Calculator.evaluate(g[0]), from = g[1].lowercased(), to = g[2].lowercased()
            let temps = ["c", "f", "k", "°c", "°f"]
            var value: Double
            if temps.contains(from), temps.contains(to) {
                let c = from.contains("f") ? (x - 32) * 5 / 9 : from == "k" ? x - 273.15 : x
                guard c >= -273.15 else { throw MathError.invalid("Temperature is below absolute zero.") }
                value = to.contains("f") ? c * 9 / 5 + 32 : to == "k" ? c + 273.15 : c
            } else {
                // Each unit maps to its dimension and a factor relative to the base unit.
                let dimensions: [[String: Double]] = [
                    ["mm": 0.001, "cm": 0.01, "m": 1, "km": 1000, "in": 0.0254, "inch": 0.0254, "inches": 0.0254, "ft": 0.3048, "feet": 0.3048, "yd": 0.9144, "mi": 1609.344, "miles": 1609.344],
                    ["mg": 0.000001, "g": 0.001, "kg": 1, "lb": 0.45359237, "lbs": 0.45359237, "oz": 0.028349523125],
                    ["ms": 0.001, "s": 1, "sec": 1, "min": 60, "h": 3600, "hr": 3600, "day": 86400, "days": 86400, "week": 604800],
                    ["ml": 0.001, "l": 1, "gal": 3.785411784],
                    ["b": 1, "kb": 1000, "mb": 1e6, "gb": 1e9, "tb": 1e12, "kib": 1024, "mib": 1048576, "gib": 1073741824, "tib": 1099511627776]
                ]
                guard let units = dimensions.first(where: { $0[from] != nil && $0[to] != nil }), let a = units[from], let b = units[to] else { throw MathError.invalid("Unknown or incompatible units. Try 10 km to mi, 72 f to c, or 2 gib to mib.") }
                value = x * a / b
            }
            guard value.isFinite else { throw MathError.invalid("Result is outside the supported range.") }
            return .init(value: value, display: Calculator.format(value) + " " + to)
        }
        return nil
    }
}
