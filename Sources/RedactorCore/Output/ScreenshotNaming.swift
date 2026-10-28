import Foundation

public enum ScreenshotNaming {
    /// The folder macOS saves screenshots to, or ~/Desktop when unset or not a writable directory.
    public static func outputDirectory(
        configured: String? = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
        fileManager: FileManager = .default
    ) -> URL {
        let desktop = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        guard let configured, !configured.isEmpty else { return desktop }
        let path = (configured as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
              fileManager.isWritableFile(atPath: path)
        else { return desktop }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// "Screenshot 2026-10-27 at 5.42.10 PM.png", with " (2)", " (3)"… on collision.
    public static func fileURL(
        in directory: URL,
        date: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = timeZone
        day.dateFormat = "yyyy-MM-dd"

        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        // macOS puts a narrow no-break space (U+202F) before AM/PM.
        time.dateFormat = "h.mm.ss\u{202F}a"

        let base = "Screenshot \(day.string(from: date)) at \(time.string(from: date))"
        var url = directory.appendingPathComponent("\(base).png")
        var n = 2
        while exists(url) {
            url = directory.appendingPathComponent("\(base) (\(n)).png")
            n += 1
        }
        return url
    }
}
