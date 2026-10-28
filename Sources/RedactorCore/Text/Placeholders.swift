import Foundation

/// `[NAME 1]`, `[ID 2]`…: what redacted values become in copied text.
enum Placeholders {
    static func label(for kind: PIIKind) -> String {
        switch kind {
        case .name: "NAME"
        case .idNumber: "ID"
        case .email: "EMAIL"
        case .phone: "PHONE"
        case .address: "ADDRESS"
        case .birthdate: "BIRTHDATE"
        case .creditCard: "CARD"
        case .link: "LINK"
        case .secret: "SECRET"
        case .manual: "REDACTED"
        }
    }

    private static let regex = try! NSRegularExpression(
        pattern: #"\[(NAME|ID|EMAIL|PHONE|ADDRESS|BIRTHDATE|CARD|LINK|SECRET|REDACTED) (\d+)\]"#
    )

    static func ranges(in text: String) -> [NSRange] {
        regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
    }

    /// `text` with every placeholder replaced by X's of the same length, so ranges stay valid and
    /// detectors see a value (a label next to `[NAME 1]` keeps its value instead of claiming the next line).
    static func masked(_ text: String) -> String {
        let out = NSMutableString(string: text)
        for range in ranges(in: text) {
            out.replaceCharacters(in: range, with: String(repeating: "X", count: range.length))
        }
        return out as String
    }

    /// Replaces each detection with its placeholder. `detections` must not overlap.
    static func apply(_ text: String, _ detections: [Detection], numbering: inout PlaceholderNumbering) -> String {
        let ns = text as NSString
        let sorted = detections.sorted { $0.range.location < $1.range.location }
        // Numbered in reading order, replaced back to front so earlier ranges stay valid.
        let replacements = sorted.map { ($0.range, numbering.placeholder(kind: $0.kind, value: ns.substring(with: $0.range))) }
        let out = NSMutableString(string: text)
        for (range, placeholder) in replacements.reversed() {
            out.replaceCharacters(in: range, with: placeholder)
        }
        return out as String
    }

    /// Numbers already in `text` per label, so new placeholders never reuse them.
    static func highestNumbers(in text: String) -> [String: Int] {
        var highest: [String: Int] = [:]
        let ns = text as NSString
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let label = ns.substring(with: m.range(at: 1))
            highest[label] = max(highest[label] ?? 0, Int(ns.substring(with: m.range(at: 2))) ?? 0)
        }
        return highest
    }
}

/// The same value gets the same placeholder everywhere in one copy.
struct PlaceholderNumbering {
    private var counters: [String: Int]
    private var assigned: [String: String] = [:]

    init(seededFrom text: String) {
        counters = Placeholders.highestNumbers(in: text)
    }

    mutating func placeholder(kind: PIIKind, value: String) -> String {
        let label = Placeholders.label(for: kind)
        let key = label + "\u{0}" + Self.normalize(value, kind: kind)
        if let existing = assigned[key] { return existing }
        let n = (counters[label] ?? 0) + 1
        counters[label] = n
        let placeholder = "[\(label) \(n)]"
        assigned[key] = placeholder
        return placeholder
    }

    /// `0917 123 4567` and `09171234567` are the same phone; `Juan  Dela Cruz` and `juan dela cruz` the same name.
    static func normalize(_ value: String, kind: PIIKind) -> String {
        switch kind {
        case .phone, .idNumber, .creditCard:
            let digits = value.filter(\.isNumber)
            return digits.isEmpty ? value.lowercased() : digits
        case .email, .link:
            return value.lowercased().filter { !$0.isWhitespace }
        case .secret:
            return value
        case .name, .address, .birthdate, .manual:
            return value.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }
}
