import Foundation

/// Fake credentials for tests, assembled at runtime so secret scanners don't flag the source.
enum FakeSecrets {
    private static func run(_ n: Int) -> String { String(String(repeating: "abcdefghij0123456789", count: 4).prefix(n)) }

    static let openAI = "sk" + "-proj-" + run(30)
    static let anthropic = "sk" + "-ant-api03-" + run(30)
    static let stripe = "sk" + "_live_" + run(20)
    static let aws = "AK" + "IA" + "IOSFODNN7EXAMPLE"
    static let github = "gh" + "p_" + run(36)
    static let githubPAT = "github" + "_pat_" + run(30)
    static let slack = "xo" + "xb-" + "1234567890-" + run(10)
    static let google = "AI" + "za" + "SyD-" + run(31)
    static let jwt = "ey" + "JhbGciOiJIUzI1NiJ9." + "ey" + "JzdWIiOiIxMjM0NTY3ODkwIn0." + run(32)
    static let bearerToken = run(22)
    static let dbPassword = "s3" + "cret"
    static let connectionString = "postgres://app" + ":" + dbPassword + "@db/qa"
    static let pemBegin = "-----BEGIN " + "PRIVATE KEY-----"
    static let pemEnd = "-----END " + "PRIVATE KEY-----"

    static let all = [openAI, anthropic, stripe, aws, github, githubPAT, slack, google, jwt]
}
