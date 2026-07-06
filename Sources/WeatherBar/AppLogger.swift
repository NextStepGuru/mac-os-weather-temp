import Foundation
import os

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private let osLogger = Logger(subsystem: "com.weatherbar.app", category: "general")
    private let logFileURL: URL
    private let maxFileSize = 1_000_000
    private let queue = DispatchQueue(label: "com.weatherbar.app.logger")

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logDir = appSupport.appendingPathComponent("WeatherBar/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        logFileURL = logDir.appendingPathComponent("weatherbar.log")
    }

    var fileURL: URL { logFileURL }

    func log(_ message: String, level: LogLevel = .info) {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] \(message)\n"

        queue.async {
            self.rotateIfNeeded()
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: self.logFileURL)
                }
            }
        }

        switch level {
        case .debug:
            osLogger.debug("\(message, privacy: .public)")
        case .info:
            osLogger.info("\(message, privacy: .public)")
        case .warning:
            osLogger.warning("\(message, privacy: .public)")
        case .error:
            osLogger.error("\(message, privacy: .public)")
        }
    }

    func readAll() -> String {
        queue.sync {
            guard let contents = try? String(contentsOf: logFileURL, encoding: .utf8),
                  !contents.isEmpty else {
                return "No log entries yet."
            }
            return contents
        }
    }

    private func rotateIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attributes[.size] as? Int,
              size > maxFileSize else { return }

        let backupURL = logFileURL.deletingLastPathComponent().appendingPathComponent("weatherbar.log.1")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: logFileURL, to: backupURL)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
