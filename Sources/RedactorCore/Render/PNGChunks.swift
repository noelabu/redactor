import Foundation

public enum PNGChunks {
    /// Chunks needed to display the image at the right size and colour. Everything else
    /// (eXIf, tEXt, iTXt, zTXt, tIME, …) is dropped.
    public static let allowed: Set<String> = ["IHDR", "PLTE", "tRNS", "pHYs", "iCCP", "sRGB", "gAMA", "cHRM", "IDAT", "IEND"]

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Rebuilds `png` with only the allowed chunks. Each chunk's CRC covers only that chunk,
    /// so the kept chunks are copied unchanged. Throws if the data isn't a well-formed PNG.
    public static func stripMetadata(_ png: Data) throws -> Data {
        let bytes = [UInt8](png)
        guard bytes.count > 8, Array(bytes[0..<8]) == signature else { throw RedactorError.encodeFailed }

        var out = Data(signature)
        var i = 8
        var sawEnd = false
        while i + 12 <= bytes.count {
            let length = Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16 | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            let end = i + 12 + length
            guard length >= 0, end <= bytes.count else { throw RedactorError.encodeFailed }
            let type = String(decoding: bytes[(i + 4)..<(i + 8)], as: UTF8.self)
            if allowed.contains(type) {
                out.append(contentsOf: bytes[i..<end])
            }
            i = end
            if type == "IEND" {
                sawEnd = true
                break
            }
        }
        guard sawEnd else { throw RedactorError.encodeFailed }
        return out
    }
}
