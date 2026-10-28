import Foundation

public enum PIIKind: String, Sendable, CaseIterable {
    case email, phone, address, link, creditCard, idNumber, name, birthdate, manual
}

public struct Detection: Sendable, Equatable {
    public let kind: PIIKind
    public let range: NSRange

    public init(kind: PIIKind, range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

public protocol Detector: Sendable {
    func detect(in text: String) -> [Detection]
}
