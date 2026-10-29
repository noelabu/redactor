import Foundation
import NaturalLanguage

/// Sanity checks on values a language model reported. The on-device model tends to fill its
/// answer with non-PII (document titles, amounts, bank names), so each value must look like
/// the kind it was reported as before it can place a box.
public enum AIFindingFilter {
    public static func accept(_ text: String, as kind: PIIKind, now: Date = Date()) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { return false }
        let digits = value.filter(\.isNumber).count
        let compact = value.filter { !$0.isWhitespace }.count

        switch kind {
        case .email:
            return !EmailDetector().detect(in: value).isEmpty
        case .phone, .idNumber, .creditCard:
            return digits >= 6 && digits * 2 >= compact && !isMoney(value)
        case .birthdate:
            return isPlausibleBirthdate(value, now: now)
        case .address:
            return value.count >= 8 && matches(addressWords, value)
        case .name:
            return digits == 0 && value.count <= 60 && (1...6).contains(value.split(separator: " ").count) && isPersonName(value)
        case .link, .manual, .secret:
            return false
        }
    }

    private static let money = try! NSRegularExpression(
        pattern: #"^(?:php|₱|p)?\s?\d{1,3}(?:,?\d{3})*\.\d{2}$"#, options: [.caseInsensitive]
    )
    private static let addressWords = try! NSRegularExpression(
        pattern: #"\b(?:st|street|ave|avenue|road|rd|blvd|brgy|bgy|barangay|city|village|subd|subdivision|province|purok|sitio|blk|block|lot|phase|zone|municipality|bldg|building|unit|floor|metro manila)\b"#,
        options: [.caseInsensitive]
    )
    private static let fourDigitYear = try! NSRegularExpression(pattern: #"\b(19|20)\d{2}\b"#)
    private static let shortNumericDate = try! NSRegularExpression(pattern: #"^\d{1,2}[/-]\d{1,2}[/-]\d{2}$"#)

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func isMoney(_ text: String) -> Bool { matches(money, text) }

    /// A date whose year is at least a year in the past (so document and pay dates fail).
    private static func isPlausibleBirthdate(_ text: String, now: Date) -> Bool {
        if matches(shortNumericDate, text) { return true }
        guard let m = fourDigitYear.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let year = Int((text as NSString).substring(with: m.range))
        else { return false }
        let thisYear = Calendar(identifier: .gregorian).component(.year, from: now)
        return year >= 1900 && year < thisYear
    }

    /// Words that mark a value as a document, organisation or place rather than a person.
    private static let nonNameWords: Set<String> = [
        "report", "revenue", "quarterly", "annual", "summary", "statement", "invoice", "receipt", "payslip",
        "form", "sheet", "information", "card", "identification", "certificate", "application",
        "team", "finance", "department", "office", "company", "corp", "corporation", "inc", "ltd", "limited",
        "group", "holdings", "services", "solutions", "bank", "government", "national", "republic", "republika",
        "pilipinas", "philippine", "philippines", "city", "street", "center", "centre", "hospital", "school",
        "university", "college", "employee", "engineer", "manager", "approved", "prepared", "total", "net",
        "gross", "pay", "salary", "account", "number", "date", "meeting", "project", "the", "of", "for", "and",
    ]
    private static let nameParticles: Set<String> = ["de", "dela", "del", "delos", "de los", "y", "van", "von", "da", "dos", "jr", "sr", "ii", "iii"]

    /// Apple's name tagger sees a person, or the value is shaped like a name: 2–5 capitalised
    /// words of letters only (lowercase particles like "dela" allowed), none of them document words.
    private static func isPersonName(_ text: String) -> Bool {
        if taggerSeesPerson(text) { return true }
        let words = text.split(whereSeparator: { $0 == " " || $0 == "," }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        guard (2...5).contains(words.count) else { return false }
        return words.allSatisfy { word in
            let lower = word.lowercased()
            guard !nonNameWords.contains(lower), word.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" }) else { return false }
            return nameParticles.contains(lower) || word.first?.isUppercase == true
        }
    }

    /// All-caps values are also tried in title case, since the tagger relies on capitalisation.
    private static func taggerSeesPerson(_ text: String) -> Bool {
        for candidate in [text, text.capitalized] {
            let tagger = NLTagger(tagSchemes: [.nameType])
            let sentence = "This is \(candidate)."
            tagger.string = sentence
            var found = false
            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .nameType,
                                 options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, _ in
                if tag == .personalName { found = true }
                return !found
            }
            if found { return true }
        }
        return false
    }
}

/// Lines likely to be Filipino, which Apple's on-device model rejects as an unsupported language.
public enum FilipinoText {
    private static let words: Set<String> = [
        "po", "opo", "ang", "ng", "mga", "sa", "ko", "yung", "ito", "iyan", "ka", "naman", "lang", "na",
        "si", "ni", "kay", "ako", "ikaw", "siya", "kami", "tayo", "sila", "natin", "namin", "nyo", "niyo",
        "hindi", "oo", "salamat", "kasi", "pala", "talaga", "kapanganakan", "pangalan", "apelyido",
        "tirahan", "petsa", "lugar", "araw", "buwan", "taon", "republika", "pilipinas", "gitnang", "kaarawan",
    ]

    public static func isLikely(_ line: String) -> Bool {
        line.lowercased().split(whereSeparator: { !$0.isLetter }).contains { words.contains(String($0)) }
    }
}
