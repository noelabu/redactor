import Foundation
import Testing
@testable import RedactorCore

private func matched(_ text: String, _ detections: [Detection]) -> [String] {
    detections.map { (text as NSString).substring(with: $0.range) }
}

@Suite struct SecretDetectorTests {
    @Test(arguments: FakeSecrets.all)
    func findsTokens(_ token: String) {
        let text = "key = \(token) # prod"
        let d = SecretDetector().detect(in: text)
        #expect(d.map(\.kind).allSatisfy { $0 == .secret })
        #expect(matched(text, d).contains(token))
    }

    @Test func redactsOnlyTheBearerToken() {
        let text = "Authorization: Bearer " + FakeSecrets.bearerToken
        #expect(matched(text, SecretDetector().detect(in: text)) == [FakeSecrets.bearerToken])
    }

    @Test func redactsOnlyTheConnectionStringCredentials() {
        let text = "DATABASE=" + FakeSecrets.connectionString
        #expect(matched(text, SecretDetector().detect(in: text)) == ["app:" + FakeSecrets.dbPassword])
    }

    @Test func findsPrivateKeyBlockAcrossLines() {
        let text = "x\n\(FakeSecrets.pemBegin)\nMIIEvQIBADANBg\nkqhkiG9w0BAQEF\n\(FakeSecrets.pemEnd)\ny"
        let found = matched(text, PrivateKeyBlockDetector().detect(in: text))
        #expect(found.count == 1)
        #expect(found.first?.hasPrefix(FakeSecrets.pemBegin) == true)
        #expect(found.first?.hasSuffix(FakeSecrets.pemEnd) == true)
    }

    @Test(arguments: [
        "a skill-based approach", "commit 3f2c9a1b7e4d5c6f8a9b0c1d2e3f4a5b6c7d8e9f", "https://example.com/path",
        "the bearer of bad news", "AKIA123", "sk-short",
    ])
    func ignoresLookalikes(_ text: String) {
        #expect(SecretDetector().detect(in: text).isEmpty)
    }
}
