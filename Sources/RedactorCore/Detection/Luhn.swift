public enum Luhn {
    /// True when `digits` (ASCII digits only) passes the Luhn checksum.
    public static func isValid(_ digits: String) -> Bool {
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return false }
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            var d = Int(String(ch))!
            if i % 2 == 1 {
                d *= 2
                if d > 9 { d -= 9 }
            }
            sum += d
        }
        return sum % 10 == 0
    }
}
