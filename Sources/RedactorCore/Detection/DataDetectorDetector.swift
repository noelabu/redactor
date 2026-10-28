import Foundation

/// Phone numbers, postal addresses and links via NSDataDetector.
public struct DataDetectorDetector: Detector {
    private static let detector = try! NSDataDetector(
        types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue
            | NSTextCheckingResult.CheckingType.link.rawValue
    )

    public init() {}

    public func detect(in text: String) -> [Detection] {
        let full = NSRange(text.startIndex..., in: text)
        return Self.detector.matches(in: text, range: full).compactMap { result in
            switch result.resultType {
            case .phoneNumber: return Detection(kind: .phone, range: result.range)
            case .address: return Detection(kind: .address, range: result.range)
            case .link:
                let kind: PIIKind = result.url?.scheme == "mailto" ? .email : .link
                return Detection(kind: kind, range: result.range)
            default: return nil
            }
        }
    }
}
