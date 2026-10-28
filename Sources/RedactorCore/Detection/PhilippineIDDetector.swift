import Foundation

/// Philippine ID numbers recognisable by format alone. Separators are required (and consistent),
/// since a bare run of digits could be anything; unseparated IDs are caught by `FieldLabels` instead.
public struct PhilippineIDDetector: Detector {
    private static let patterns: [NSRegularExpression] = [
        #"\b\d{3}([- ])\d{3}\1\d{3}(?:\1\d{3,5})?\b"#,          // TIN 123-456-789(-000)
        #"\b\d{2}([- ])\d{7}\1\d\b"#,                           // SSS 34-1234567-8
        #"\b\d{2}([- ])\d{9}\1\d\b"#,                           // PhilHealth 12-345678901-2
        #"\b\d{4}([- ])\d{4}\1\d{4}(?:\1\d{4})?\b"#,            // Pag-IBIG MID 1234-5678-9012, PhilSys PSN/PCN 16 digits
        #"\b\d{4}([- ])\d{7}\1\d\b"#,                           // UMID CRN 0111-1234567-8
        #"\b(?:[A-Z]\d{7}[A-Z]|[A-Z]{2}\d{7})\b"#,              // Passport P1234567A, EB1234567
        #"\b[A-Z]\d{2}-\d{2}-\d{6}\b"#,                         // LTO licence N01-23-456789
    ].map { try! NSRegularExpression(pattern: $0) }

    public init() {}

    public func detect(in text: String) -> [Detection] {
        let full = NSRange(text.startIndex..., in: text)
        return Self.patterns.flatMap { regex in
            regex.matches(in: text, range: full).map { Detection(kind: .idNumber, range: $0.range) }
        }
    }
}
