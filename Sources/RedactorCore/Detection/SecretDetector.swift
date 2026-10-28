import Foundation

/// Credentials recognisable by format: API keys, tokens, and the password in a connection string.
/// Keys whose value is a secret (`DB_PASSWORD=…`) are caught by `CodeKeys` instead.
public struct SecretDetector: Detector {
    // Each pattern's first capture group, when present, is the part to redact.
    private static let patterns: [NSRegularExpression] = [
        #"\bsk-(?:proj-|ant-[a-z0-9]+-)?[A-Za-z0-9_-]{20,}"#,              // OpenAI, Anthropic
        #"\b[rs]k_(?:live|test)_[A-Za-z0-9]{16,}"#,                         // Stripe
        #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#,                                  // AWS access key ID
        #"\bgh[pousr]_[A-Za-z0-9]{36,}\b"#,                                 // GitHub
        #"\bgithub_pat_[A-Za-z0-9_]{22,}"#,
        #"\bxox[abposr]-[A-Za-z0-9-]{10,}"#,                                // Slack
        #"\bAIza[0-9A-Za-z_-]{35}"#,                                        // Google API key
        #"\beyJ[\w-]{8,}\.eyJ[\w-]{8,}\.[\w-]{8,}"#,                        // JWT
        #"(?i)\bbearer\s+([A-Za-z0-9._~+/=-]{16,})"#,                       // Authorization: Bearer …
        #"\b[a-z][a-z0-9+.-]*://([^\s:/@]+:[^\s@/]+)@"#,                    // scheme://user:pass@host
    ].map { try! NSRegularExpression(pattern: $0) }

    public init() {}

    public func detect(in text: String) -> [Detection] {
        let full = NSRange(location: 0, length: (text as NSString).length)
        return Self.patterns.flatMap { regex in
            regex.matches(in: text, range: full).map { m in
                let range = m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range
                return Detection(kind: .secret, range: range)
            }
        }
    }
}

/// PEM private keys. The only rule that spans lines, so it runs on whole text, not per line.
public struct PrivateKeyBlockDetector: Detector {
    private static let regex = try! NSRegularExpression(
        pattern: #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#
    )

    public init() {}

    public func detect(in text: String) -> [Detection] {
        let full = NSRange(location: 0, length: (text as NSString).length)
        return Self.regex.matches(in: text, range: full).map { Detection(kind: .secret, range: $0.range) }
    }
}
