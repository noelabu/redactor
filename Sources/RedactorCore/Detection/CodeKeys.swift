import Foundation

/// `key → value` pairs in code, config and logs: `"full_name": "Juan"`, `firstName: Juan`,
/// `date_of_birth=1990-01-15`, `export DB_PASSWORD="…"`, `?email=…&mobile=…`. Unlike form labels,
/// a key can sit anywhere on a line, so one line of JSON can hold several.
enum CodeKeys {
    // Key (quoted, or bare with an optional `export`), then `:`, `=` or `=>` (group 4).
    private static let keyRegex = try! NSRegularExpression(
        pattern: #"(?:"([A-Za-z_][\w.-]*)"|'([A-Za-z_][\w.-]*)'|(?<![\w.$-])(?:export\s+)?([A-Za-z_][\w.-]*))\s*(=>|:|=)(?![=:/])\s*"#
    )
    private static let camelBoundary = try! NSRegularExpression(pattern: #"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])"#)
    private static let emptyValues: Set<String> = ["null", "nil", "none", "true", "false", "undefined"]

    static func matches(in line: String) -> [FieldLabelMatch] {
        let ns = line as NSString
        var result: [FieldLabelMatch] = []
        var searchFrom = 0
        while searchFrom < ns.length,
              let m = keyRegex.firstMatch(in: line, range: NSRange(location: searchFrom, length: ns.length - searchFrom)) {
            searchFrom = NSMaxRange(m.range)
            let keyRange = [1, 2, 3].map { m.range(at: $0) }.first { $0.location != NSNotFound }!
            guard let kind = kind(forKey: ns.substring(with: keyRange)),
                  let value = valueRange(in: ns, from: NSMaxRange(m.range), separator: ns.substring(with: m.range(at: 4)))
            else { continue }
            result.append(FieldLabelMatch(kind: kind, labelRange: NSRange(location: m.range.location, length: NSMaxRange(m.range) - m.range.location), valueRange: value))
            searchFrom = NSMaxRange(value)
        }
        return result
    }

    // OCR often reads an info icon after the key as one stray character ("billing_address O").
    private static let bareKey = try! NSRegularExpression(pattern: #"^\s*([A-Za-z_][\w.-]*)(?:\s+\S)?\s*$"#)

    /// A line that is only a key, as in a field-name column (`employee_name`): a standalone label
    /// whose value sits in the neighbouring box.
    static func standaloneKey(in line: String) -> FieldLabelMatch? {
        let ns = line as NSString
        guard let m = bareKey.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              let kind = kind(forKey: ns.substring(with: m.range(at: 1)))
        else { return nil }
        return FieldLabelMatch(kind: kind, labelRange: m.range(at: 1), valueRange: nil)
    }

    /// The value starting at `start`: inside quotes if quoted; otherwise up to whitespace or `&,;`
    /// after `=`, or up to `,;}]` or the end of the line after `:`. Nil for empty, null-like,
    /// nested (`{`, `[`) or variable-reference (`$`) values.
    private static func valueRange(in ns: NSString, from start: Int, separator: String) -> NSRange? {
        guard start < ns.length else { return nil }
        let first = ns.character(at: start)
        let range: NSRange
        if first == 0x22 || first == 0x27 {   // " or '
            var i = start + 1
            while i < ns.length, ns.character(at: i) != first {
                i += ns.character(at: i) == 0x5C ? 2 : 1   // skip the escaped character after \
            }
            range = NSRange(location: start + 1, length: min(i, ns.length) - start - 1)
        } else {
            let stops = separator == "=" ? CharacterSet.whitespaces.union(CharacterSet(charactersIn: "&,;")) : CharacterSet(charactersIn: ",;}]")
            var i = start
            while i < ns.length, let scalar = Unicode.Scalar(ns.character(at: i)), !stops.contains(scalar) { i += 1 }
            range = trimmed(NSRange(location: start, length: i - start), in: ns)
        }
        let value = ns.substring(with: range)
        guard !value.isEmpty, !emptyValues.contains(value.lowercased()),
              let head = value.first, !"{[$".contains(head),
              value.contains(where: { $0.isLetter || $0.isNumber })
        else { return nil }
        return range
    }

    private static func trimmed(_ range: NSRange, in ns: NSString) -> NSRange {
        var start = range.location, end = NSMaxRange(range)
        func isSpace(_ i: Int) -> Bool { Unicode.Scalar(ns.character(at: i)).map(CharacterSet.whitespaces.contains) ?? false }
        while start < end, isSpace(start) { start += 1 }
        while end > start, isSpace(end - 1) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    /// `firstName`, `first-name`, `user.first_name` → `first_name`.
    static func normalize(_ key: String) -> String {
        let last = key.split(separator: ".").last.map(String.init) ?? key
        let spaced = camelBoundary.stringByReplacingMatches(in: last, range: NSRange(location: 0, length: (last as NSString).length), withTemplate: "_")
        return spaced.lowercased().split(whereSeparator: { $0 == "_" || $0 == "-" }).joined(separator: "_")
    }

    /// `*_name` is a person's name (`taxpayer_name`, `employee_name`) unless the word before `name`
    /// says it names a thing: a bank, a file, a field, a server.
    private static let thingNames: Set<String> = [
        "bank", "branch", "file", "filename", "field", "column", "table", "schema", "database", "db",
        "host", "hostname", "server", "domain", "app", "application", "project", "repo", "package",
        "module", "class", "function", "method", "type", "model", "product", "item", "document",
        "doc", "form", "template", "key", "bucket", "queue", "topic", "service", "env", "region",
        "zone", "cluster", "container", "image", "tag", "label", "event", "job", "task", "step",
        "status", "state", "country", "city", "province", "street", "font", "color", "variable",
        "param", "parameter", "property", "attribute", "header", "cookie", "index", "role", "group",
        "team", "plan", "tier", "category", "section", "page", "tab", "view", "route", "path",
        "dir", "folder", "device", "browser", "os", "platform", "network", "interface", "node", "pod",
    ]
    private static let names: Set<String> = ["surname", "given_names", "fullname", "firstname", "lastname", "middlename"]
    private static let birthdates: Set<String> = ["dob", "date_of_birth", "birth_date", "birthdate", "birthday"]
    private static let ids: Set<String> = [
        "tin", "sss", "gsis", "philhealth", "pagibig", "pag_ibig", "hdmf", "umid", "crn", "philsys", "psn", "pcn",
        "passport", "drivers_license", "driver_license", "national_id", "ssn", "tax_id", "prc", "voter_id",
        "bank_account", "iban",
    ]
    /// Too generic alone (`"license": "MIT"`, `"account": "prod"`); count only with a number suffix.
    private static let idsWithSuffixOnly: Set<String> = ["license", "account"]
    private static let phones: Set<String> = ["phone", "mobile", "cellphone", "telephone", "msisdn"]
    private static let secretWords: Set<String> = ["password", "passwd", "pwd", "secret", "token", "credential", "credentials", "cookie", "dsn"]
    private static let secretPhrases = [
        "api_key", "apikey", "access_key", "private_key", "signing_key", "client_secret",
        "connection_string", "session_id",
    ]
    /// `token_count`, `password_field`: about the secret, not the secret.
    private static let notSecretTails: Set<String> = ["count", "type", "limit", "length", "size", "ttl", "expiry", "expires", "path", "file", "name", "header", "field", "url", "env"]
    private static let addressHosts: Set<String> = ["ip", "mac", "bind", "listen", "server", "host", "remote", "local", "base", "wallet"]

    static func kind(forKey key: String) -> PIIKind? {
        let k = normalize(key)
        let parts = k.split(separator: "_").map(String.init)
        guard let tail = parts.last else { return nil }

        let isSecret = parts.contains(where: secretWords.contains) || secretPhrases.contains(where: k.contains)
        if isSecret && !notSecretTails.contains(tail) { return .secret }

        if tail == "email" || k == "e_mail" || k == "email_address" { return .email }
        if birthdates.contains(k) { return .birthdate }
        if names.contains(k) || (tail == "name" && parts.count >= 2 && !thingNames.contains(parts[parts.count - 2])) { return .name }

        var base = k
        var hadSuffix = false
        for suffix in ["_number", "_no", "_num", "_nr"] where base.hasSuffix(suffix) && base.count > suffix.count {
            base = String(base.dropLast(suffix.count))
            hadSuffix = true
        }
        if ids.contains(base) || (hadSuffix && idsWithSuffixOnly.contains(base)) { return .idNumber }
        let baseTail = base.split(separator: "_").last.map(String.init) ?? base
        if phones.contains(baseTail) || base == "tel" || (hadSuffix && base == "contact") { return .phone }

        if k == "place_of_birth" || k == "street" || k == "address1" || k == "address2" { return .address }
        if parts.contains("address") && !parts.contains(where: addressHosts.contains) { return .address }
        return nil
    }
}
