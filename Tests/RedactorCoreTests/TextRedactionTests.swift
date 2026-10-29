import Foundation
import Testing
@testable import RedactorCore

@Suite struct PlaceholderTests {
    @Test func sameValueSamePlaceholder() async throws {
        let r = try await TextRedactionEngine.run("Mail juan@x.com, cc JUAN@x.com and maria@x.com")
        #expect(r.text == "Mail [EMAIL 1], cc [EMAIL 1] and [EMAIL 2]")
    }

    @Test func phonesMatchByDigits() async throws {
        let r = try await TextRedactionEngine.run("Mobile: 0917 123 4567\nCall 09171234567 later")
        #expect(r.text == "Mobile: [PHONE 1]\nCall [PHONE 1] later")
    }

    @Test func numbersContinueAfterExistingPlaceholders() async throws {
        let r = try await TextRedactionEngine.run("[NAME 3] wrote to juan@x.com\nName: Maria Santos")
        #expect(r.text == "[NAME 3] wrote to [EMAIL 1]\nName: [NAME 4]")
    }
}

@Suite struct TextRedactionTests {
    @Test func labelledFieldsAndIDs() async throws {
        let text = "Name: Juan Dela Cruz\nTIN: 123-456-789-000\nPosition: QA Analyst"
        let r = try await TextRedactionEngine.run(text)
        #expect(r.text == "Name: [NAME 1]\nTIN: [ID 1]\nPosition: QA Analyst")
        #expect(r.replacements == 2)
    }

    @Test func standaloneLabelTakesNextLine() async throws {
        let r = try await TextRedactionEngine.run("Address\n123 Rizal St., Brgy. San Antonio, Makati City")
        #expect(r.text == "Address\n[ADDRESS 1]")
    }

    @Test func headingDoesNotSwallowParagraph() async throws {
        let text = "Contact\nPlease reach out to the support team if the extraction keeps failing on the second page of the upload."
        let r = try await TextRedactionEngine.run(text)
        #expect(!r.changed)
    }

    @Test func aiAddsUnlabelledNames() async throws {
        let r = try await TextRedactionEngine.run("Prepared by Maria Santos, maria@x.com", ai: FakeAI(names: ["Maria Santos"]))
        #expect(r.text == "Prepared by [NAME 1], [EMAIL 1]")
        #expect(r.aiStatus == .used(skippedLines: 0))
    }

    @Test func leavesCleanTextAlone() async throws {
        let text = "Fixed the parser bug on page 2.\nhttps://qa.example.com/documents/8812/review"
        let r = try await TextRedactionEngine.run(text)
        #expect(!r.changed)
        #expect(r.text == text)
    }

    @Test func linksStayButPIIInsideIsRedacted() async throws {
        let r = try await TextRedactionEngine.run("See https://qa.example.com/doc/8812?email=juan@x.com&tab=fields")
        #expect(r.text == "See https://qa.example.com/doc/8812?email=[EMAIL 1]&tab=fields")
    }

    @Test func idempotent() async throws {
        let first = try await TextRedactionEngine.run("Name: Juan Dela Cruz\nTIN: 123-456-789-000\nAddress\n12 Rizal St, Makati City")
        let second = try await TextRedactionEngine.run(first.text)
        #expect(first.changed)
        #expect(!second.changed)
        #expect(second.text == first.text)
    }

    @Test func placeholdersDoNotTriggerLabels() async throws {
        let text = "Name: [NAME 1]\nID: [ID 1]\nJuan"
        let r = try await TextRedactionEngine.run(text)
        #expect(r.text == text)
    }

    @Test func keepsLineEndingsAndOffsets() async throws {
        let r = try await TextRedactionEngine.run("Hi 👋🏽\r\nmail juan@x.com\r\nbye")
        #expect(r.text == "Hi 👋🏽\r\nmail [EMAIL 1]\r\nbye")
    }

    @Test func serviceAccountJSONStaysValid() async throws {
        let key = FakeSecrets.pemBegin + #"\nMIIEvQIBADANBgkqhkiG9w0BAQEF\n"# + FakeSecrets.pemEnd + #"\n"#
        let json = """
            {
              "type": "service_account",
              "project_id": "boost-qa",
              "private_key_id": "a1b2c3d4e5f6a7b8c9d0",
              "private_key": "\(key)",
              "client_email": "qa-bot@boost-qa.iam.gserviceaccount.com"
            }
            """
        let r = try await TextRedactionEngine.run(json)
        #expect(r.text.contains(#""type": "service_account""#))
        #expect(!r.text.contains("MIIEvQ"))
        #expect(!r.text.contains("a1b2c3d4"))
        #expect(!r.text.contains("qa-bot@"))
        #expect((try? JSONSerialization.jsonObject(with: Data(r.text.utf8))) != nil)
    }

    @Test func envFile() async throws {
        let env = "PORT=8080\nOPENAI_API_KEY=\(FakeSecrets.openAI)\nDATABASE_URL=\(FakeSecrets.connectionString)\nDEBUG=true"
        let r = try await TextRedactionEngine.run(env)
        #expect(r.text == "PORT=8080\nOPENAI_API_KEY=[SECRET 1]\nDATABASE_URL=postgres://[SECRET 2]@db/qa\nDEBUG=true")
    }

    @Test func doubleCheckCatchesWhatFirstPassHid() async throws {
        let pipeline = DetectionPipeline(detectors: [DoubleCheckTests.ContextSensitive()])
        let r = try await TextRedactionEngine.run("Header REF-778812", pipeline: pipeline, ai: FakeAI(names: ["Header"]))
        #expect(r.addedByDoubleCheck >= 1)
        #expect(!r.text.contains("REF-"))
    }

    @Test func failsClosedWhenPIIRemains() async throws {
        /// Finds "first1" first; once a placeholder is on the line, finds the next "wN" each pass.
        struct Endless: Detector {
            func detect(in text: String) -> [Detection] {
                let pattern = text.contains("XXX") ? #"\bw\d\b"# : "first1"
                let r = (text as NSString).range(of: pattern, options: .regularExpression)
                return r.location == NSNotFound ? [] : [Detection(kind: .idNumber, range: r)]
            }
        }
        await #expect(throws: TextRedactionError.residualPII) {
            try await TextRedactionEngine.run("first1 w1 w2 w3 w4", pipeline: DetectionPipeline(detectors: [Endless()]), blockDetectors: [])
        }
    }

    @Test func rulesStillApplyWhenAIFails() async throws {
        struct Boom: Error {}
        let r = try await TextRedactionEngine.run("Prepared by Maria Santos, maria@x.com", ai: FakeAI(error: Boom()))
        guard case .failed = r.aiStatus else { Issue.record("expected .failed, got \(r.aiStatus)"); return }
        #expect(r.text == "Prepared by Maria Santos, [EMAIL 1]")
    }

    @Test func longTextSkipsAI() async throws {
        final class Calls: @unchecked Sendable {
            let lock = NSLock()
            var count = 0
        }
        struct RecordingAI: LinePIIDetector {
            let calls: Calls
            func detect(lines: [String]) async throws -> LinePIIResult {
                calls.lock.withLock { calls.count += 1 }
                return LinePIIResult(detections: [])
            }
        }
        let calls = Calls()
        let text = String(repeating: "plain words here\n", count: TextRedactionEngine.aiCharacterLimit / 10)
        let r = try await TextRedactionEngine.run(text, ai: RecordingAI(calls: calls))
        #expect(r.aiStatus == .off)
        #expect(calls.count == 0)
    }
}

@Suite struct RepeatedValueTests {
    @Test func fieldNameColumnTakesValueAndItsCopy() async throws {
        let r = try await TextRedactionEngine.run("employee_name\nREYES, ERNESTO, JR.\nREYES, ERNESTO, JR.")
        #expect(r.text == "employee_name\n[NAME 1].\n[NAME 1].")
    }

    @Test func redactsSameValueElsewhere() {
        let lines = ["Name: Juan Dela Cruz", "Signed by JUAN DELA CRUZ today"]
        let found = LineRules.detect(lines: lines, pipeline: .text, neighbor: nil)
        #expect(found.contains(LineDetection(line: 1, range: NSRange(location: 10, length: 14), kind: .name)))
    }
}
