import Foundation

/// Pure log-export helpers kept separate from AppKit so they can be tested.
enum LogExporter {
    static func fileName(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "weatherbar-\(formatter.string(from: date)).log"
    }

    static func write(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
