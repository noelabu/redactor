import Foundation

public struct EmailDetector: Detector {
    // Tolerates OCR inserting a space around "@".
    private static let regex = try! NSRegularExpression(
        pattern: #"[A-Z0-9._%+-]+\s?@\s?[A-Z0-9.-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive]
    )

    public init() {}

    public func detect(in text: String) -> [Detection] {
        let full = NSRange(text.startIndex..., in: text)
        return Self.regex.matches(in: text, range: full).map { Detection(kind: .email, range: $0.range) }
    }
}

public struct CreditCardDetector: Detector {
    private static let regex = try! NSRegularExpression(
        pattern: #"\b(?:\d[ -]?){12,18}\d\b"#
    )

    public init() {}

    public func detect(in text: String) -> [Detection] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return Self.regex.matches(in: text, range: full).compactMap { match in
            let digits = ns.substring(with: match.range).filter(\.isNumber)
            guard (13...19).contains(digits.count), Luhn.isValid(digits) else { return nil }
            return Detection(kind: .creditCard, range: match.range)
        }
    }
}
