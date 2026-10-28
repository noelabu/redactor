import CoreGraphics
import Foundation

/// A form label found on an OCR line, e.g. "Date of Birth:".
public struct FieldLabelMatch: Sendable, Equatable {
    public let kind: PIIKind
    public let labelRange: NSRange
    /// The value after the label on the same line, or nil when the label stands alone
    /// and its value sits in a neighbouring box.
    public let valueRange: NSRange?
}

/// Labelled form fields (English and Tagalog) whose values are PII, as on Philippine forms and IDs.
public enum FieldLabels {
    private static let labels: [(PIIKind, [String])] = [
        (.name, [
            "full name", "last name", "first name", "middle name", "surname", "given names?",
            "mother'?s maiden name", "mother'?s name", "father'?s name", "spouse'?s name", "spouse",
            "employee name", "account name", "taxpayer'?s name", "payee", "name",
            "mga pangalan", "gitnang apelyido", "gitnang pangalan", "pangalan", "apelyido",
        ]),
        (.birthdate, [
            "date of birth", "birth ?date", "dob", "kaarawan", "petsa ng kapanganakan",
        ]),
        (.address, [
            "home address", "permanent address", "present address", "residential address",
            "registered address", "mailing address", "address", "residence", "place of birth",
            "tirahan", "lugar ng kapanganakan",
        ]),
        (.phone, [
            "mobile", "cellphone", "cell", "contact", "telephone", "tel",
        ]),
        (.idNumber, [
            "tax identification", "tin", "sss", "gsis", "philhealth", "pin", "pag-?ibig", "hdmf", "mid",
            "umid", "crn", "philsys", "psn", "pcn", "passport", "driver'?s licen[cs]e", "prc licen[cs]e", "prc id", "licen[cs]e",
            "prc", "postal id", "prn", "voter'?s id", "vin", "precinct", "account", "id",
        ]),
    ]

    // Label, then an optional "No." / "Number" / "#" (group 1), then an optional colon (group 2).
    // OCR often turns ' into ’, so accept both.
    private static let regexes: [(PIIKind, NSRegularExpression)] = labels.map { kind, words in
        let alternation = words.joined(separator: "|").replacingOccurrences(of: "'?", with: "['’]?")
        let pattern = #"\b(?:"# + alternation + #")\b(\s*(?:no\.?|number|num\.?|#))?\s*(:)?"#
        return (kind, try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
    }

    private static let leadingNumbering = try! NSRegularExpression(pattern: #"^\s*(?:\(?\d{1,2}[a-z]?[.)]\s*)?"#, options: [.caseInsensitive])

    /// Labels on `line`. A label counts when followed by a colon, or when it starts the line
    /// (after optional "4." / "4a)") and either stands alone, has a "No." suffix, or is an
    /// ID/birthdate label followed by digits. Each value runs up to the next label.
    public static func matches(in line: String) -> [FieldLabelMatch] {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        let lineStart = leadingNumbering.firstMatch(in: line, range: full).map { NSMaxRange($0.range) } ?? 0
        if let bilingual = bilingualLabel(line) { return [bilingual] }

        var found: [(kind: PIIKind, label: NSRange)] = []
        for (kind, regex) in regexes {
            for m in regex.matches(in: line, range: full) {
                let hasColon = m.range(at: 2).location != NSNotFound
                if !hasColon {
                    guard m.range.location == lineStart else { continue }
                    let rest = ns.substring(from: NSMaxRange(m.range))
                    let standalone = trimmed(NSRange(location: NSMaxRange(m.range), length: ns.length - NSMaxRange(m.range)), in: ns) == nil
                    let hasSuffix = m.range(at: 1).location != NSNotFound
                    let numericValue = (kind == .idNumber || kind == .birthdate) && rest.contains(where: \.isNumber)
                    guard standalone || hasSuffix || numericValue else { continue }
                }
                // Earlier label lists win (e.g. "mother's maiden name" over "name").
                if found.contains(where: { NSIntersectionRange($0.label, m.range).length > 0 }) { continue }
                found.append((kind, m.range))
            }
        }
        found.sort { $0.label.location < $1.label.location }

        return found.enumerated().map { i, f in
            let start = NSMaxRange(f.label)
            let end = i + 1 < found.count ? found[i + 1].label.location : ns.length
            return FieldLabelMatch(kind: f.kind, labelRange: f.label, valueRange: trimmed(NSRange(location: start, length: end - start), in: ns))
        }
    }

    /// A line made only of labels joined by "/", as on Philippine IDs ("Apelyido / Last Name"):
    /// one standalone label whose value is in the neighbouring box.
    private static func bilingualLabel(_ line: String) -> FieldLabelMatch? {
        let ns = line as NSString
        let parts = line.split(separator: "/", omittingEmptySubsequences: false).map { String($0) }
        guard parts.count >= 2 else { return nil }
        var firstKind: PIIKind?
        for part in parts {
            let p = part.trimmingCharacters(in: .whitespaces)
            let pr = NSRange(location: 0, length: (p as NSString).length)
            guard let (kind, _) = regexes.first(where: { _, regex in
                regex.firstMatch(in: p, options: [.anchored], range: pr).map { $0.range == pr } ?? false
            }) else { return nil }
            if firstKind == nil { firstKind = kind }
        }
        guard let kind = firstKind, let range = trimmed(NSRange(location: 0, length: ns.length), in: ns) else { return nil }
        return FieldLabelMatch(kind: kind, labelRange: range, valueRange: nil)
    }

    /// The range of `line` that is a value: up to its first label, or the whole line.
    /// Nil when nothing precedes its first label (the line is another label, not a value).
    public static func valueRange(ofNeighbor line: String) -> NSRange? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        let lineStart = leadingNumbering.firstMatch(in: line, range: full).map { NSMaxRange($0.range) } ?? 0
        let end = matches(in: line).first?.labelRange.location ?? ns.length
        guard end > lineStart else { return nil }
        return trimmed(NSRange(location: 0, length: end), in: ns)
    }

    /// Index of the box holding a standalone label's value: the nearest box to the right on the
    /// same row, else the nearest box directly below. Rects are pixels, top-left origin.
    public static func neighbor(of label: CGRect, among candidates: [CGRect]) -> Int? {
        let h = label.height
        let right = candidates.indices.filter { i in
            let c = candidates[i]
            let overlap = min(label.maxY, c.maxY) - max(label.minY, c.minY)
            return overlap >= 0.5 * min(h, c.height) && c.minX >= label.maxX - h * 0.5 && c.minX - label.maxX <= 20 * h
        }
        if let best = right.min(by: { candidates[$0].minX < candidates[$1].minX }) { return best }

        let below = candidates.indices.filter { i in
            let c = candidates[i]
            let gap = c.minY - label.maxY
            let horizontal = c.minX < label.maxX + 2 * h && c.maxX > label.minX - 2 * h
            return gap >= -0.3 * h && gap <= 2.5 * h && horizontal
        }
        return below.min(by: { candidates[$0].minY < candidates[$1].minY })
    }

    private static let valueCharacters = CharacterSet.alphanumerics

    /// Shrinks `range` to its first..last alphanumeric character; nil if it has none.
    private static func trimmed(_ range: NSRange, in ns: NSString) -> NSRange? {
        var start = range.location, end = NSMaxRange(range)
        func isValue(_ i: Int) -> Bool {
            let c = ns.substring(with: NSRange(location: i, length: 1)).unicodeScalars.first!
            return valueCharacters.contains(c)
        }
        while start < end, !isValue(start) { start += 1 }
        while end > start, !isValue(end - 1) { end -= 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }
}
