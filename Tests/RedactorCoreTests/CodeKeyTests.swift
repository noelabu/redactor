import Foundation
import Testing
@testable import RedactorCore

@Suite struct CodeKeyTests {
    func values(_ line: String) -> [(PIIKind, String?)] {
        FieldLabels.matches(in: line).map { m in
            (m.kind, m.valueRange.map { (line as NSString).substring(with: $0) })
        }
    }

    @Test(arguments: [
        (#"  "full_name": "Juan Dela Cruz","#, PIIKind.name, "Juan Dela Cruz"),
        ("firstName: 'Juan'", .name, "Juan"),
        ("date_of_birth=1990-01-15", .birthdate, "1990-01-15"),
        ("sss_number: 34-1234567-8", .idNumber, "34-1234567-8"),
        ("customer.mobileNumber => 09171234567", .phone, "09171234567"),
        (#""client_email": "svc@proj.iam.gserviceaccount.com","#, .email, "svc@proj.iam.gserviceaccount.com"),
        ("home_address: 12 Rizal St, Makati", .address, "12 Rizal St"),
    ])
    func findsValue(_ line: String, _ kind: PIIKind, _ value: String) {
        let v = values(line)
        #expect(v.map(\.0) == [kind])
        #expect(v.map(\.1) == [value])
    }

    @Test func secretKeys() {
        let line = "export DB_" + "PASSWORD=\"" + FakeSecrets.dbPassword + "\""
        #expect(values(line).map(\.0) == [.secret])
        #expect(values(line).map(\.1) == [FakeSecrets.dbPassword])
    }

    @Test func findsSeveralKeysOnOneJSONLine() {
        let v = values(#"{"email": "a@b.co", "mobile_number": "09171234567", "status": "ok"}"#)
        #expect(v.map(\.0) == [.email, .phone])
        #expect(v.map(\.1) == ["a@b.co", "09171234567"])
    }

    @Test func findsQueryParameters() {
        let v = values("https://qa.example.com/doc/8812?email=juan@x.com&mobile=09171234567&tab=fields")
        #expect(v.map(\.1) == ["juan@x.com", "09171234567"])
    }

    @Test func takesWholeEscapedPrivateKey() {
        let key = FakeSecrets.pemBegin + #"\nMIIEvQ\n"# + FakeSecrets.pemEnd + #"\n"#
        #expect(values(#""private_key": ""# + key + #"","#).map(\.1) == [key])
    }

    @Test(arguments: [
        #""name": "redactor""#, #""id": 42"#, #""version": "1.0""#, #""token": null"#, #""address": {"#,
        #""license": "MIT""#, "max_tokens: 1024", "token_count=12", "ip_address: 10.0.0.4", "if a == b", "pwd=$HOME",
    ])
    func ignores(_ line: String) {
        #expect(values(line).isEmpty)
    }

    @Test func formLabelStopsAtNextCodeKey() {
        let v = values("Name: Juan Dela Cruz   Email: juan@x.com")
        #expect(v.map(\.0) == [.name, .email])
        #expect(v.map(\.1) == ["Juan Dela Cruz", "juan@x.com"])
    }

    @Test(arguments: [("firstName", "first_name"), ("APIKey", "api_key"), ("user.date-of-birth", "date_of_birth")])
    func normalizesKeys(_ key: String, _ expected: String) {
        #expect(CodeKeys.normalize(key) == expected)
    }
}

@Suite struct StandaloneKeyTests {
    @Test(arguments: [
        ("employee_name", PIIKind.name),
        ("  date_of_birth ", .birthdate),
        ("tin_number", .idNumber),
        ("customerMobile", .phone),
    ])
    func bareKeyIsStandaloneLabel(_ line: String, _ kind: PIIKind) {
        let m = FieldLabels.matches(in: line)
        #expect(m.map(\.kind) == [kind])
        #expect(m.first?.valueRange == nil)
    }

    @Test(arguments: [
        "taxpayer_name", "account_holder_name", "registrant_name", "payee_name", "user.signatoryName",
        "trade_name", "business_name",
    ])
    func anyPersonOrBusinessNameKey(_ line: String) {
        #expect(FieldLabels.matches(in: line).map(\.kind) == [.name])
    }

    @Test(arguments: [
        "document_type", "status", "file_name", "employer_tin extra words", "bank_name", "branch_name",
        "table_name", "hostName", "document_title",
    ])
    func ignoresOtherKeys(_ line: String) {
        #expect(FieldLabels.matches(in: line).isEmpty)
    }
}

@Suite struct ReviewToolLabelTests {
    @Test func keyWithInfoIconReadAsLetter() {
        #expect(FieldLabels.matches(in: "billing_address O").map(\.kind) == [.address])
        #expect(FieldLabels.matches(in: "account_number 0").map(\.kind) == [.idNumber])
    }

    @Test func accountHolderNameIsANameLabel() {
        let m = FieldLabels.matches(in: "Account Holder Name")
        #expect(m.map(\.kind) == [.name])
        #expect(m.first?.valueRange == nil)
    }
}
