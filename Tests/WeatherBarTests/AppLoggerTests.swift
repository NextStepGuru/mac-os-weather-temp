import Foundation
import Testing
@testable import WeatherBar

struct AppLoggerTests {
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeatherBarTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func readAllEmptyReturnsPlaceholder() {
        let dir = makeTempDirectory()
        let logger = AppLogger(directory: dir)

        #expect(logger.readAll() == "No log entries yet.")
    }

    @Test func logWritesMessageWithLevel() async {
        let dir = makeTempDirectory()
        let logger = AppLogger(directory: dir)

        logger.log("test message", level: .info)

        try? await Task.sleep(nanoseconds: 100_000_000)

        let contents = logger.readAll()
        #expect(contents.contains("[INFO]"))
        #expect(contents.contains("test message"))
    }

    @Test func rotationMovesToBackup() async {
        let dir = makeTempDirectory()
        let logger = AppLogger(directory: dir, maxFileSize: 50)

        logger.log("first entry that should trigger rotation", level: .info)
        logger.log("second entry after rotation", level: .info)

        try? await Task.sleep(nanoseconds: 200_000_000)

        let backupURL = dir.appendingPathComponent("weatherbar.log.1")
        #expect(FileManager.default.fileExists(atPath: backupURL.path))

        let current = logger.readAll()
        #expect(current.contains("second entry after rotation"))
    }
}
